# Bootstrap: everything that other stacks and CI stand on, and every IAM
# resource in this repository. Only the operator applies it, with the
# long-lived credentials of the operator host (README, "Break-glass"); CI
# plans it on pull requests and never applies it. The CI apply role has no
# IAM permission at all, so nothing CI runs can widen its own access.
#
# - the state bucket (it holds its own state: first run on local state)
# - the IAM OIDC provider for GitHub Actions
# - the plan role (pull requests, read-only) and the apply role (production
#   environment) for this repository's Terraform workflow
# - one deploy role per site, for the content deploy of the site repository
# - the read-only role of the stats job that reads the access logs

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition
}

module "state_bucket" {
  source = "../../modules/state-bucket"

  bucket_name = var.state_bucket_name
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

module "terraform_ci_roles" {
  source = "../../modules/terraform-ci-roles"

  oidc_provider_arn    = aws_iam_openid_connect_provider.github.arn
  github_repository    = var.github_repository
  apply_environment    = var.apply_environment
  state_bucket_name    = module.state_bucket.bucket_name
  managed_bucket_names = concat([var.log_bucket_name], [for s in values(var.sites) : s.bucket_name])
  hosted_zone_ids      = distinct([for s in values(var.sites) : s.zone_id])
}

module "deploy_role" {
  source   = "../../modules/github-deploy-role"
  for_each = { for site, s in var.sites : site => s if s.distribution_id != null }

  role_name         = "${replace(each.key, ".", "-")}-github-deploy"
  oidc_provider_arn = aws_iam_openid_connect_provider.github.arn
  github_repository = each.value.repository
  bucket_arn        = "arn:${local.partition}:s3:::${each.value.bucket_name}"
  distribution_arn  = "arn:${local.partition}:cloudfront::${var.aws_account_id}:distribution/${each.value.distribution_id}"
}

module "log_reader" {
  source = "../../modules/log-reader-role"

  role_name      = var.log_reader_role_name
  log_bucket_arn = "arn:${local.partition}:s3:::${var.log_bucket_name}"
  principal_arns = var.log_reader_principal_arns
}
