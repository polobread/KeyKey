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
session through OIDC. The upload role cannot delete objects or write outside
`keykey/releases/download/`. Release paths receive a one-year CloudFront cache lifetime
using `s-maxage`, while browsers revalidate before reusing a download. After an
upload the workflow invalidates only the exact paths it changed, which also
supports the repository's same-tag recovery builds.

## Provision AWS

Copy the example variables and apply with the pre-created Terraform deploy role:

```sh
cd terraform/infra
cp terraform.tfvars.example terraform.tfvars
terraform init
terraform plan
terraform apply
terraform output
```

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

For a Terraform deployment workflow, use the `terraform` GitHub Environment
and set `AWS_TERRAFORM_DEPLOY_ROLE_ARN` to
`arn:aws:iam::679046566270:role/keykey-github-terraform-deploy`.

After these variables exist, every successful macOS, Windows, or Linux publish
uploads the same verified files to GitHub and S3. A mirror failure fails the
publishing job visibly; rerunning the job safely replaces the same S3 key and
S3 versioning preserves the prior object for 90 days.

Existing releases are not copied automatically. To backfill one, manually run
each applicable package workflow with its existing `release_tag`; the normal
recovery path rebuilds, verifies, republishes, and mirrors that platform.
