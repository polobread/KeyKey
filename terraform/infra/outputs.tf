output "aws_account_id" {
  description = "Value for the release environment variable AWS_ACCOUNT_ID."
  value       = data.aws_caller_identity.current.account_id
}

output "aws_region" {
  description = "Value for AWS_RELEASE_MIRROR_REGION."
  value       = var.aws_region
}

output "bucket_name" {
  description = "Value for AWS_RELEASE_MIRROR_BUCKET."
  value       = aws_s3_bucket.releases.id
}

output "cloudfront_distribution_id" {
  description = "Value for AWS_RELEASE_MIRROR_DISTRIBUTION_ID."
  value       = aws_cloudfront_distribution.releases.id
}

output "cloudfront_domain_name" {
  description = "CloudFront target for an optional custom DNS alias."
  value       = aws_cloudfront_distribution.releases.domain_name
}

output "mirror_base_url" {
  description = "Value for AWS_RELEASE_MIRROR_BASE_URL."
  value       = "https://${var.domain_name}"
}

output "github_actions_role_arn" {
  description = "Value for AWS_RELEASE_MIRROR_ROLE_ARN."
  value       = data.aws_iam_role.github_release_service.arn
}
