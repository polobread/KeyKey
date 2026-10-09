variable "aws_region" {
  description = "AWS Region for the S3 origin."
  type        = string
  default     = "ap-east-2"
}

variable "bucket_name" {
  description = "Globally unique private S3 bucket name for release assets."
  type        = string
}

variable "github_release_role_name" {
  description = "Pre-created GitHub OIDC role that receives the release upload policy."
  type        = string
  default     = "keykey-github-release-service"
}

variable "domain_name" {
  description = "Public hostname for the CloudFront release mirror."
  type        = string
  default     = "download.aws.polobread.com"
}

variable "hosted_zone_id" {
  description = "Route 53 public hosted zone that owns domain_name."
  type        = string
  default     = "Z01457382FBLRWQELDR4Z"
}

variable "price_class" {
  description = "CloudFront edge-location price class."
  type        = string
  default     = "PriceClass_200"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200, or PriceClass_All."
  }
}
