data "aws_caller_identity" "current" {}

resource "aws_acm_certificate" "releases" {
  provider          = aws.us_east_1
  domain_name       = var.domain_name
  validation_method = "DNS"

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = {
    for option in aws_acm_certificate.releases.domain_validation_options :
    option.domain_name => {
      name   = option.resource_record_name
      record = option.resource_record_value
      type   = option.resource_record_type
    }
  }

  zone_id = var.hosted_zone_id
  name    = each.value.name
  type    = each.value.type
  ttl     = 60
  records = [each.value.record]
}

resource "aws_acm_certificate_validation" "releases" {
  provider                = aws.us_east_1
  certificate_arn         = aws_acm_certificate.releases.arn
  validation_record_fqdns = [for record in aws_route53_record.certificate_validation : record.fqdn]
}

resource "aws_s3_bucket" "releases" {
  bucket = var.bucket_name
}

resource "aws_s3_bucket_public_access_block" "releases" {
  bucket = aws_s3_bucket.releases.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_ownership_controls" "releases" {
  bucket = aws_s3_bucket.releases.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_versioning" "releases" {
  bucket = aws_s3_bucket.releases.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "releases" {
  bucket = aws_s3_bucket.releases.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "releases" {
  bucket = aws_s3_bucket.releases.id

  rule {
    id     = "expire-replaced-assets"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = 90
    }
  }

  depends_on = [aws_s3_bucket_versioning.releases]
}

resource "aws_cloudfront_origin_access_control" "releases" {
  name                              = "${var.bucket_name}-oac"
  description                       = "Private S3 access for the KeyKey release mirror"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_cache_policy" "releases" {
  name        = "keykey-release-assets"
  comment     = "Immutable GitHub Release mirror paths"
  default_ttl = 31536000
  max_ttl     = 31536000
  min_ttl     = 1

  parameters_in_cache_key_and_forwarded_to_origin {
    enable_accept_encoding_brotli = false
    enable_accept_encoding_gzip   = false

    cookies_config {
      cookie_behavior = "none"
    }

    headers_config {
      header_behavior = "none"
    }

    query_strings_config {
      query_string_behavior = "none"
    }
  }
}

resource "aws_cloudfront_response_headers_policy" "releases" {
  name    = "keykey-release-assets"
  comment = "Security headers for release downloads"

  security_headers_config {
    content_type_options {
      override = true
    }

    referrer_policy {
      override        = true
      referrer_policy = "no-referrer"
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = true
      override                   = true
      preload                    = true
    }
  }
}

resource "aws_cloudfront_distribution" "releases" {
  enabled         = true
  is_ipv6_enabled = true
  comment         = "KeyKey GitHub Release download mirror"
  price_class     = var.price_class
  aliases         = [var.domain_name]

  origin {
    domain_name              = aws_s3_bucket.releases.bucket_regional_domain_name
    origin_id                = "release-s3-origin"
    origin_access_control_id = aws_cloudfront_origin_access_control.releases.id

    s3_origin_config {
      origin_access_identity = ""
    }
  }

  default_cache_behavior {
    target_origin_id           = "release-s3-origin"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = false
    cache_policy_id            = aws_cloudfront_cache_policy.releases.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.releases.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.releases.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }
}

resource "aws_route53_record" "releases_ipv4" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "A"

  alias {
    name                   = aws_cloudfront_distribution.releases.domain_name
    zone_id                = aws_cloudfront_distribution.releases.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "releases_ipv6" {
  zone_id = var.hosted_zone_id
  name    = var.domain_name
  type    = "AAAA"

  alias {
    name                   = aws_cloudfront_distribution.releases.domain_name
    zone_id                = aws_cloudfront_distribution.releases.hosted_zone_id
    evaluate_target_health = false
  }
}

data "aws_iam_policy_document" "cloudfront_read" {
  statement {
    sid       = "AllowCloudFrontReadOnly"
    actions   = ["s3:GetObject"]
    resources = ["${aws_s3_bucket.releases.arn}/*"]

    principals {
      type        = "Service"
      identifiers = ["cloudfront.amazonaws.com"]
    }

    condition {
      test     = "StringEquals"
      variable = "AWS:SourceArn"
      values   = [aws_cloudfront_distribution.releases.arn]
    }
  }
}

resource "aws_s3_bucket_policy" "cloudfront_read" {
  bucket = aws_s3_bucket.releases.id
  policy = data.aws_iam_policy_document.cloudfront_read.json

  depends_on = [aws_s3_bucket_public_access_block.releases]
}

data "aws_iam_role" "github_release_service" {
  name = var.github_release_role_name
}

data "aws_iam_policy_document" "github_release_mirror" {
  statement {
    sid = "ListMultipartUploads"
    actions = [
      "s3:ListBucketMultipartUploads",
    ]
    resources = [aws_s3_bucket.releases.arn]
  }

  statement {
    sid = "WriteAndVerifyReleaseAssets"
    actions = [
      "s3:AbortMultipartUpload",
      "s3:GetObject",
      "s3:ListMultipartUploadParts",
      "s3:PutObject",
    ]
    resources = ["${aws_s3_bucket.releases.arn}/keykey/releases/download/*"]
  }

  statement {
    sid       = "InvalidateReplacedReleaseAssets"
    actions   = ["cloudfront:CreateInvalidation"]
    resources = [aws_cloudfront_distribution.releases.arn]
  }
}

resource "aws_iam_role_policy" "github_release_mirror" {
  name   = "release-mirror-upload"
  role   = data.aws_iam_role.github_release_service.id
  policy = data.aws_iam_policy_document.github_release_mirror.json
}
