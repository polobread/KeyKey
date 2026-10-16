# Installer

Builds `chichi77KeyKey.pkg` with `pkgbuild` and `productbuild`. The original 1.1
installer was made with PackageMaker, which Apple deprecated and which cannot
sign its output.

## Prerequisites

Xcode, and Homebrew's `openssl@3`:

    brew install openssl@3

## Building from scratch

From the repository root. `make` verifies the checked-in shared dictionary;
platform builds do not rebuild the production model. Prepare the pinned updater SDK
before building the app.

    cd Source/Distributions/Takao/DatabaseCooker && make && cd -

    python3 update/prepare.py fetch macos

    cd Source
    xcodebuild -project Takao.xcodeproj -target "Takao (Loader OSX-IMK)" \
        -configuration Release -xcconfig Takao-macOS.xcconfig build
    cd -

    cd Installer && ./build.sh

`build.sh` takes the app path as its first argument and defaults to
`../Source/build/Release/chichi77 KeyKey.app`. The app is staged in a temporary
root. Nested code and the app are re-signed ad hoc for local builds after
framework headers are removed. `pkgbuild` assigns root:wheel itself.

It writes two files: `chichi77KeyKey.pkg` to install, and `chichi77KeyKey.pkg.zip`
to attach to a release.

## Installing your own build

A package you built locally has no quarantine attribute, so Gatekeeper does not
inspect it and it installs unsigned without any ceremony:

    sudo installer -pkg Installer/chichi77KeyKey.pkg -target / \
      && ls -ld "/Library/Input Methods/chichi77 KeyKey.app"

The `ls` matters. `installer` reports success even when it has written the
payload somewhere else, so confirm the bundle actually landed before going any
further.

The package includes a standalone, signed `KeyKeyInputSourceTool`.
`postinstall` runs it in the current console user's GUI session and credentials.
The helper captures existing KeyKey process identities, registers the installed
bundle with `TISRegisterInputSource`, confirms the source can be found by ID,
and requests normal termination of only the captured installed processes.
macOS can launch the installed version when the user selects KeyKey.
The helper never calls enable, disable or select APIs and does not read private
HIToolbox preferences. It does not infer pre-install settings from the state
after the bundle was replaced. First installs and intentionally disabled sources
are not automatically enabled.

The operation has a 20-second deadline; normal old-process exit is limited to
3 seconds. Failures and timeouts cannot leave a source disabled by this helper.
A failed setup opens a separate GUI warning with an Open Keyboard Settings
button, without keeping Installer waiting for a response. The warning and log
distinguish file installation from input-source setup. The completed payload
does not become a package failure. No console user or a non-startup target
volume defers setup to Keyboard settings. Other login sessions are not refreshed.
See [investigation, Apple references, and validation limits](../docs/MACOS_INPUT_SOURCE_UPGRADE.md).

After installation, select KeyKey from the Input menu and verify typing in
TextEdit and the version in Preferences. For an upgrade, selecting ABC and then
KeyKey again can activate a new session. Add a missing entry through Keyboard
settings; an existing entry does not need to be removed first. If typing works,
no logout is required. A first installation may still need a new login before
macOS lists the source. Do not use repeated logout/forced shutdown as a recovery
loop for the reported hang. Registration and confirmed old-process exit do not
prove that a new IMK session can type; real installation acceptance is separate.

Run isolated regressions without installing or changing input sources:

```sh
bash Installer/test-input-sources.sh
```

The app payload and standalone helper are arm64 only. Packaging rejects other
app architectures; the isolated tests also compile explicitly for arm64.

## Signing and notarising

Only needed to hand the package to someone else. Both certificates come with an
Apple Developer Program membership; there is no way to obtain a Developer ID
without one.

    DEVELOPER_ID_APPLICATION="Developer ID Application: Your Name (TEAMID)" \
    DEVELOPER_ID_INSTALLER="Developer ID Installer: Your Name (TEAMID)" \
    NOTARY_PROFILE=chichi77 \
    ./build.sh

Each variable is independent and each is a no-op when unset.
`DEVELOPER_ID_APPLICATION` signs the two frameworks and the three helper apps
before the outer bundle, with Hardened Runtime and a secure timestamp, both of
which notarisation requires. `DEVELOPER_ID_INSTALLER` signs the package.
`NOTARY_PROFILE` submits it and staples the ticket, so verification works
offline; store the profile first with

    xcrun notarytool store-credentials chichi77 --apple-id ... --team-id ...

Signing without notarising is not enough. A Developer ID signature alone is
rejected on current macOS.

Before any of that, `build.sh` deletes `Headers` from the staged frameworks. The
framework targets sign their own output while those headers are still in place,
and the app's Copy Files phase then strips them, leaving the seal listing files
that are gone. `codesign --verify --deep --strict` fails on that and the notary
service rejects it. Headers are of no use at runtime.

Local packages re-sign the staged app ad hoc and verify its seal. They remain
unsigned at the installer level and are not notarized.

Release builds use `CODE_SIGN_INJECT_BASE_ENTITLEMENTS[config=Release] = NO`
in `Takao-macOS.xcconfig`; Debug builds keep their debugger access. The signing
helper removes only `com.apple.security.get-task-allow` from existing
entitlements, preserving Sparkle's sandbox/XPC and other runtime permissions.
It checks all Mach-O slices after signing and fails if permissions change or
debug access remains. Different runtime permissions between universal slices
are rejected rather than silently replaced by the runner's native slice.

`NOTARY_PROFILE` uses `update/notarize-macos.py`: it saves the JSON submission
response, stderr and the downloadable Apple report in a separate attempt
directory under `Installer/notarization-logs/` (override with `NOTARY_LOG_DIR`).
It staples and validates only when `submit --wait` exits successfully **and**
the JSON status is `Accepted`. Rejections, timeouts, malformed responses and
missing status stop packaging; a failed log download does not hide the original
rejection. When using a non-default signing keychain, set `KEYCHAIN` too.

Run the isolated regressions from the repository root:

```sh
python3 -m unittest discover -s update -p 'test_macos_signing.py' -v
python3 -m unittest discover -s update -p 'test_macos_notarization.py' -v
```

On macOS, the signing test also compiles temporary universal helper/XPC/framework
fixtures and re-signs them ad hoc. Notarization tests mock Apple responses;
neither test installs an input method, accesses private signing identities,
submits to Apple, or publishes a Release. Successful tests do not prove actual
Developer ID notarization or Gatekeeper installation acceptance.

## Signing in GitHub Actions

The `publish` job of `.github/workflows/package-macos.yml` does the same thing
on a version tag, from a keychain it builds and throws away. Three details are
not obvious:

  - `security set-key-partition-list` has to run after the import, or `codesign`
    and `productbuild` wait for a GUI authorisation that never comes and the job
    hangs until it times out.
  - A `.p12` exported from Keychain Access holds the leaf identities but not the
    Apple intermediate that issued them, so the job also imports
    `https://www.apple.com/certificateauthority/DeveloperIDCA.cer`. Without it
    `codesign` cannot build a chain.
  - `notarytool store-credentials` writes the profile into that same keychain,
    which is also made the default keychain, so the `--keychain-profile` lookup
    above resolves without being passed a path.

The signing job uploads only the `NOTARY_LOG_DIR` diagnostics as
`keykey-macos-notary-VERSION-ATTEMPT` even when signing/notarization fails.
It never uploads the temporary keychain or certificate files. A rejection
cannot proceed to signed installer/Release/CDN publication.

Verifying a `.p12` by hand needs one more: do not put the scratch keychain under
`mktemp -d`. `/var` is a symlink to `private/var`, `securityd` stores the
resolved path, and looking it up again by the `/var` spelling reports
`The specified keychain could not be found`. Use a path under `$HOME`.

## Distributing

`chichi77KeyKey.pkg.zip` is what to attach to a release: browsers and GitHub
handle a zip predictably, and it extracts to `chichi77KeyKey.pkg` with nothing
wrapped around it.

An unsigned package that has been downloaded carries a quarantine attribute and
Gatekeeper refuses it. Since macOS 15 the Control-click and Open shortcut no
longer bypasses this, so the recipient has to go to System Settings, Privacy &
Security and choose Open Anyway, or clear the attribute first:

    xattr -d com.apple.quarantine chichi77KeyKey.pkg

## Why relocation is pinned off

`pkgbuild` marks app bundles relocatable by default. `installer` then looks for
an existing copy of the same bundle identifier anywhere on the disk, writes the
payload over that instead of the path the package specifies, and still reports
that the install succeeded. A build directory is enough to trigger it. An input
method only runs from the path Text Input Services scans, so `build.sh` runs
`pkgbuild --analyze` and sets `BundleIsRelocatable` to false before building.

`PackageInfo` in the finished package should read `relocatable="false"` with an
empty `<relocate/>`.

## Where the version and the minimum OS come from

The package version is read from the app's `Info.plist`. The minimum system
version lives in `distribution.plist` as `allowed-os-versions`; passing
`--product` alongside `--distribution` has no effect, which is why the old
`requirement.plist` never applied.
