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
- `KeyKeySettingsBackend.dll`;
- `KeyKeyDeployment.exe` and the x86 registration bridge;
- the packaged `WinSparkle.dll`; and
- the outer NSIS installer containing the signed payload files.

Signatures must use SHA-256 and an RFC 3161 timestamp. The release workflow must
verify every returned Authenticode signature before calculating checksums and
publishing an artifact. Files must not be modified after signing.

The Windows assets in release `v1.2.9` predate the SignPath integration and
remain unsigned. This policy applies after the SignPath Foundation application
is accepted and the verified signing workflow is enabled.

## Source review and merge

All source, documentation, build-script, and CI changes, including agent-assisted
changes, are committed and pushed to a working branch. They reach `master` only
through a pull request reviewed and merged by [polobread](https://github.com/polobread).
Agents must not commit or push directly to `master`, merge PRs, or enable auto-merge.

This repository's maintainer-controlled PR process supports the
[SignPath Foundation conditions](https://signpath.org/terms.html): contributions
from non-committers require team review, and each release requires manual signing
approval. Build scripts and CI configuration are part of that review. PR approval
and signing approval are separate decisions made by the maintainer.

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

The desktop updater is default-off and transfers release/version requests only
after a manual check or explicit opt-in. Ed25519 signatures protect downloaded
updates separately from Authenticode. The stable update-metadata tool rejects
unsigned or untimestamped Windows installers; the existing unsigned CI artifacts
are test/manual-download artifacts, not automatic-update candidates. See
[desktop update setup](Updates/README.md). The SignPath approval requirement remains unchanged.
