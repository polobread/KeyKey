# Code signing policy

Windows publisher signing uses a maintainer-held Certum code-signing certificate
through SimplySign. The certificate has been issued; the first real signed-package
and deployment acceptance is tracked separately from isolated tooling tests.

## Scope and release process

This policy covers official Windows release artifacts for chichi77 KeyKey. Only
artifacts built from the source and build workflows in this repository may be
submitted for signing. Release builds originate from version tags, are built by
GitHub Actions, and are downloaded and verified against the exact tag/source commit,
CI run and artifact digest before local signing. The maintainer connects SimplySign
with a phone token (and PIN if required), then a local script signs and packages.
Publication requires a separate explicit tag/SHA-256 approval after VM acceptance.
See [Windows Certum release procedure](docs/WINDOWS_CERTUM_RELEASE.md).

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

Previously published unsigned Windows assets remain unchanged. The original
`Package Windows` unsigned build/package/publish/mirror workflow remains intact,
but its jobs are disabled unless `WINDOWS_RELEASE_MODE` is explicitly `unsigned`.
The separate `Prepare Windows Signing Inputs` workflow runs when the variable is
unset or `certum`, and only produces signing inputs. Other values disable both.
The maintainer may switch back to unsigned if the certificate is not renewed;
expiry or signing failure never triggers an automatic downgrade.
Signed GitHub assets are uploaded without replacement, read back, then verified
again on Windows before the protected OIDC mirror adds immutable S3 objects.
Neither signing nor publication stores a thumbprint, OTP, PIN or TOTP seed in Git
or tool logs. Embedded public certificates remain part of Authenticode signatures.

When Windows publisher signing is unavailable, including a decision not to renew
the Certum certificate, the maintainer may explicitly select the unsigned fallback.
The maintainer permits unsigned
EXE installers on the stable update channel only when each release manifest
explicitly declares `windows_signing: "unsigned-transition"`. These releases
still require reviewed tag builds, version verification, immutable HTTPS assets,
and an Ed25519 signature made with the reviewed update key. The verifier accepts
only an actually unsigned installer, never an invalid or untrusted Authenticode
signature. Update notes disclose the missing Windows publisher signature.

Once publisher signing is available, publish a higher product version using
`windows_signing: "authenticode"` (the default), complete signing and timestamping
before Ed25519 signing, and keep the same stable feed and update key. Do not
replace an already published unsigned artifact in place. Signing authorization
and release publication remain separate manual decisions.

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
