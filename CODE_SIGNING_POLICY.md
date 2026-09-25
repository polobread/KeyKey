# Code signing policy

Free code signing provided by [SignPath.io](https://signpath.io/), certificate
by [SignPath Foundation](https://signpath.org/).

## Scope and release process

This policy covers official Windows release artifacts for chichi77 KeyKey. Only
artifacts built from the source and build workflows in this repository may be
submitted for signing. Release builds originate from version tags, are built by
GitHub Actions, and require manual approval before a SignPath signing request is
completed.

The intended signing coverage is:

- the x64 `KeyKeyTsf.dll`;
- the x86 `KeyKeyTsf.dll`;
- `KeyKeySettings.exe`;
- `KeyKeySettingsBackend.dll`; and
- the outer NSIS installer containing the signed payload files.

Signatures must use SHA-256 and an RFC 3161 timestamp. The release workflow must
verify every returned Authenticode signature before calculating checksums and
publishing an artifact. Files must not be modified after signing.

The Windows assets in release `v1.2.9` predate the SignPath integration and
remain unsigned. This policy applies after the SignPath Foundation application
is accepted and the verified signing workflow is enabled.

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
systems. Information is transferred only when a user explicitly invokes an
operating-system feature such as sharing text or downloading an application
release. See the project [privacy policy](PRIVACY.md) for details.
