# GitHub Release download mirror

This stack creates a private, versioned S3 origin and a public CloudFront
distribution. GitHub Actions uploads only the desktop assets that passed the
existing package and checksum validation. Mirrored downloads live below the
dedicated `/keykey` prefix:

```text
https://github.com/polobread/KeyKey/releases/download/v1.3.2/FILE
https://download.aws.polobread.com/keykey/releases/download/v1.3.2/FILE
```

S3 Block Public Access remains enabled. CloudFront reads the bucket through an
Origin Access Control (OAC), while GitHub Actions receives a short-lived AWS
session through OIDC. The upload role cannot delete objects. It can write release assets under
`keykey/releases/download/` and XML feeds under `keykey/update/stable/*.xml` or
`keykey/update/beta/*.xml`, not arbitrary
files outside those scopes. Release paths receive a one-year CloudFront cache lifetime
using `s-maxage`, while browsers revalidate before reusing a download. After an
upload the workflow invalidates only the exact paths it changed, which also
supports the repository's same-tag recovery builds.

Stable XML feeds have a separate CloudFront cache behavior: minimum TTL 0,
default TTL 60 seconds, maximum TTL 300 seconds. The feed publisher sets edge
TTL 60 seconds and browser revalidation, invalidates exact feed paths, waits
for completion, and verifies CDN bytes. This leaves release-asset caching unchanged.

## Bootstrap persistent state once

Terraform cannot create the S3 bucket containing its own remote state. In the
AWS Console, create the private bucket named
`keykey-terraform-state-679046566270` in `ap-east-2`, then enable **Block all
public access**, **Bucket owner enforced** object ownership, **versioning**, and
default **SSE-S3** encryption. Do not configure it as a website or CloudFront
origin.

On the Console-created `keykey-github-terraform-deploy` role, add a second
inline policy named `release-mirror-terraform-state` using
[`bootstrap/terraform-deploy-state-policy.json`](bootstrap/terraform-deploy-state-policy.json).
It grants access only to this stack's state object and S3 lockfile; it does not
change the role's existing release-mirror resource policy.

The backend state object is:

```text
s3://keykey-terraform-state-679046566270/keykey/release-mirror/terraform.tfstate
```

It is versioned and protected by the adjacent `.tflock` object. The GitHub
workflow supplies this backend from `backend.hcl.example`; do not commit a
local `terraform.tfstate` file.

## Deploy from GitHub Actions

The [Terraform Release Mirror workflow](../../.github/workflows/terraform-release-mirror.yml)
is manual only and accepts `plan` or `apply`. It runs exclusively from `master`,
uses the protected `terraform` GitHub Environment, and applies the plan created
in that same run. It never applies on a push or pull request.

Create the `terraform` GitHub Environment with required reviewers, then add
these non-secret environment variables:

| GitHub variable | Value |
|---|---|
| `AWS_ACCOUNT_ID` | `679046566270` |
| `AWS_TERRAFORM_DEPLOY_ROLE_ARN` | `arn:aws:iam::679046566270:role/keykey-github-terraform-deploy` |
| `AWS_TERRAFORM_STATE_BUCKET` | `keykey-terraform-state-679046566270` |

Run the workflow with `plan` first and inspect the output. Run it again with
`apply` only after approval. Its checked-in
`terraform.tfvars.example` supplies the mirror bucket name, hostname, hosted
zone, and `ap-east-2` origin region.

The account-wide GitHub OIDC provider and the two bootstrap roles are managed
outside this stack so Terraform never needs permission to create or modify its
own trust boundary:

| AWS role | Exact GitHub OIDC subject |
|---|---|
| `keykey-github-terraform-deploy` | `repo:polobread/KeyKey:environment:terraform` |
| `keykey-github-release-service` | `repo:polobread/KeyKey:environment:release` |

The deploy role creates the mirror resources and manages only the upload
role's `release-mirror-upload` inline policy. The stack reads the existing
upload role by `github_release_role_name`; it does not own or replace that
role's trust policy.

The stack creates the regional mirror resources in `ap-east-2` and owns
`download.aws.polobread.com` in the existing public hosted zone
`Z01457382FBLRWQELDR4Z` (`aws.polobread.com`). It requests the required ACM
certificate in `us-east-1`, creates its DNS validation record, waits for
validation, and then creates IPv4 and IPv6 Route 53 Alias records for the
CloudFront distribution. Override `domain_name` or `hosted_zone_id` only when
deploying the stack to a different DNS zone.

## Configure the GitHub release environment

Under **Settings → Environments → release → Environment variables**, create
these non-secret variables from the Terraform outputs:

| GitHub variable | Terraform output |
|---|---|
| `AWS_ACCOUNT_ID` | `aws_account_id` |
| `AWS_RELEASE_MIRROR_REGION` | `aws_region` |
| `AWS_RELEASE_MIRROR_BUCKET` | `bucket_name` |
| `AWS_RELEASE_MIRROR_DISTRIBUTION_ID` | `cloudfront_distribution_id` |
| `AWS_RELEASE_MIRROR_BASE_URL` | `mirror_base_url` |
| `AWS_RELEASE_MIRROR_ROLE_ARN` | `github_actions_role_arn` |

No AWS access key or GitHub secret is needed. Keep the existing `release`
environment deployment rules: they are also part of the OIDC boundary.

After these variables exist, every successful macOS, Windows, or Linux publish
uploads the same verified files to GitHub and S3. A mirror failure fails the
publishing job visibly; rerunning the job safely replaces the same S3 key and
S3 versioning preserves the prior object for 90 days.

Existing releases are not copied automatically. To backfill one, manually run
each applicable package workflow with its existing `release_tag`; the normal
recovery path rebuilds, verifies, republishes, and mirrors that platform.

## Stable and beta XML feed sync

After reviewed Terraform plan/apply deploys the new feed permissions/cache policy,
the [Sync Update Feeds to CDN workflow](../../.github/workflows/sync-update-feeds.yml)
uploads `update/stable/*.xml` and `update/beta/*.xml` when either changes on `master`. It reuses the same
protected `release` environment variables and OIDC role. PR runs only validate.
Manual dispatch from `master` backfills existing feeds; queued/retried publishers
always check out current master and sync all current XML files to avoid restoring
an older event snapshot or dropping another platform's change.

The destination is `s3://BUCKET/keykey/update/CHANNEL/FILE.xml`, exposed at
`https://download.aws.polobread.com/keykey/update/CHANNEL/FILE.xml`, where CHANNEL
is exactly `stable` or `beta`. Both use the short-cache policy; their XML paths
and IAM object scopes remain separate. All feeds are validated before any upload.
The added
IAM statement grants only `s3:PutObject`/`s3:GetObject` for this XML scope and
`cloudfront:GetInvalidation` for the existing distribution's completion waiter.
There is no delete permission, feed signing, JSON upload, installer publication,
or Git write in this workflow. Repository deletion does not remove remote objects;
publish an empty-item RSS to disable a feed. Partial failures can be retried;
existing S3 versioning preserves prior objects for recovery.

Source/workflow changes alone do not deploy IAM or CloudFront changes. Run the
manual Terraform workflow with `plan`, review, then `apply` before the first feed
sync; no Terraform apply or production upload is performed by local tests.
