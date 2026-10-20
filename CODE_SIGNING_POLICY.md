# Code signing policy

Windows publisher signing uses a maintainer-held Certum code-signing certificate
through SimplySign. The certificate has been issued; the first real signed-package
and deployment acceptance is tracked separately from isolated tooling tests.

## Scope and release process

This policy covers official Windows release artifacts for chichi77 KeyKey. Release
builds use a clean local checkout of the exact reviewed tag commit already merged
into master. Build-WindowsRelease.ps1 performs the full x64/x86 build and release
check matrix locally; the check-only Windows workflow uses the same script.
Release-Windows.ps1 records the source, test results and input hashes, signs
copies, and creates the EXE, both installation ZIPs, checksums and build-info.
There is no CI artifact download or CI-run requirement. The maintainer connects
SimplySign with a phone token (and PIN if required), then signs locally.
Publication requires separate approval of the complete build-info SHA-256 after VM acceptance.
See [Windows local release procedure](docs/WINDOWS_CERTUM_RELEASE.md).

The intended signing coverage is:

- the x64 `KeyKeyTsf.dll`;
- the x86 `KeyKeyTsf.dll`;
- `KeyKeySettings.exe`;
- `KeyKeySettingsBackend.dll`;
- `KeyKeyDeployment.exe` and the x86 registration bridge;
- the packaged `WinSparkle.dll`; and
- the outer NSIS installer containing the signed payload files.

Signatures must use SHA-256 and an RFC 3161 timestamp. The release workflow must
verify every returned Authenticode signature before calculating checksums and
publishing an artifact. Files must not be modified after signing.

All new Windows release assets require valid Authenticode and RFC 3161 timestamps.
This includes every EXE/DLL inside x64 and x86 ZIPs, as well as the outer NSIS EXE.
Manifests, ZIPs and checksum files are generated only after payload signing.
Windows Checks is a build/test gate, with no release artifact upload or publication.
The old signing-input workflow and unsigned release-mode selector are removed.
UnsignedTest is restricted to isolated development fixtures and never the official local release entry point.

Signed assets are uploaded without replacement and read back, then independently
verified on Windows before the protected OIDC mirror conditionally adds S3 objects.
Published legacy unsigned assets remain unchanged; compatibility verification for
those versions does not authorize producing a new unsigned release.

Windows update Ed25519 signing is local and uses keykey-update-private.pem.
The key must never be committed, staged, uploaded, printed or copied into a build
artifact. Git ignores the filename and Windows release preflight rejects a tracked
or staged copy. Only the local crypto tool reads its contents; signing diagnostics
are suppressed. Authenticode completes before Ed25519. Metadata/feed promotion
remains a separate maintainer-reviewed PR; other platform release flows are unchanged.

## Source review and merge

All source, documentation, build-script, and CI changes, including agent-assisted
changes, are committed and pushed to a working branch. They reach `master` only
through a pull request reviewed and merged by [polobread](https://github.com/polobread).
Agents must not commit or push directly to `master`, merge PRs, or enable auto-merge.

Contributions from non-committers require maintainer review. Build scripts and CI
configuration are part of that review. PR approval, SimplySign authorization and
publication approval are separate decisions made by the maintainer.

## Team roles

- Authors and committers: [polobread](https://github.com/polobread)
- Reviewer for contributions from non-committers:
  [polobread](https://github.com/polobread)
- Signing approver: [polobread](https://github.com/polobread)

The maintainer uses multi-factor authentication for repository and signing
service access. Signing approval is separate from the automated build, and no
signing credential or private key is stored in the repository.

## Privacy

The input-method functionality does not transfer entered text, keystrokes,
candidate selections, preferences, or other user information to networked
systems. Sharing text through an operating-system feature requires an explicit
user action. See the project [privacy policy](PRIVACY.md) for details.

The desktop updater defaults to weekly release/version checks and preserves saved
opt-outs. Users can disable checks; beta updates still require explicit opt-in.
Checks do not prefetch installers or authorize installation. Ed25519 signatures protect downloaded
updates separately from Authenticode. The stable update-metadata tool requires
timestamped Authenticode by default; the explicit unsigned transition above is
the only exception. Unsigned CI artifacts are not automatically promoted to
update candidates. See [desktop update setup](update/README.md).
