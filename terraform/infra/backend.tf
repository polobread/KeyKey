terraform {
  # Values are supplied by backend.hcl.example in GitHub Actions. Terraform
  # deliberately cannot create the bucket that stores its own state.
  backend "s3" {}
}
