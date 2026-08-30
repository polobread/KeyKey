# Installer

Builds `chichi77KeyKey.pkg` with `pkgbuild` and `productbuild`. The original 1.1
installer was made with PackageMaker, which Apple deprecated and which cannot
sign its output.

## Prerequisites

Xcode, and Homebrew's `openssl@3`:

    brew install openssl@3

## Building from scratch

Three steps, from the repository root. The dictionary only needs re-cooking
when something under `Source/DataTables` or `Source/Distributions/Takao/OnlineData`
changes.

    cd Source/Distributions/Takao/DatabaseCooker && make && cd -

    cd Source
    xcodebuild -project Takao.xcodeproj -target "Takao (Loader OSX-IMK)" \
        -configuration Release -xcconfig Takao-macOS.xcconfig build
    cd -

    cd Installer && ./build.sh

`build.sh` takes the app path as its first argument and defaults to
`../Source/build/Release/chichi77 KeyKey.app`. The app is staged in a temporary
root, so nothing is written into the working tree and pkgbuild assigns
root:wheel itself.

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

On a first install, log out and back in -- that is when Text Input Services
scans `/Library/Input Methods` -- then add the input source under System
Settings, Keyboard, Input Sources. Upgrading over a version that is already
installed and enabled needs neither: `postinstall` ends the running input
method and Text Input Services starts the new one in its place.

The Installer completion screen deliberately does not force a logout. It tells
first-time users to sign out when convenient while letting upgrades finish
without interrupting the current session.

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
