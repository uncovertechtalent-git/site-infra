# Shared by every site: the access log bucket (with the read-only role for the
# stats job) and the IAM OIDC provider for GitHub Actions.

module "log_bucket" {
  source = "../../modules/log-bucket"

  bucket_name           = var.log_bucket_name
  retention_days        = var.log_retention_days
  reader_principal_arns = var.log_reader_principal_arns
}

# One per account. Off until the OIDC deploy path is approved.
resource "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_oidc ? 1 : 0

  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}
