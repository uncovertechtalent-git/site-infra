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
# - one deploy role per site, for the content deploy of the site repository, and a data role for a site
#   whose data a scheduled job publishes under its own prefix
# - the read-only role of the stats job that reads the access logs

data "aws_partition" "current" {}

locals {
  partition = data.aws_partition.current.partition

  # The data role of a site is named here once: the role is created with this name, and the key policy of the signing
  # key names the same string. It is not a reference, so the key and the role do not depend on each other.
  data_role_name = { for site, s in var.sites : site => "${replace(site, ".", "-")}-github-data" if s.data_prefix != null }
}

module "state_bucket" {
  source = "../../modules/state-bucket"

  bucket_name             = var.state_bucket_name
  writer_principal_arns   = [module.terraform_ci_roles.apply_role_arn]
  operator_principal_arns = var.operator_principal_arns
  operator_only_keys      = ["site-infra/bootstrap.tfstate*", "site-infra/tfvars/*"]
}

resource "aws_iam_openid_connect_provider" "github" {
  url            = "https://token.actions.githubusercontent.com"
  client_id_list = ["sts.amazonaws.com"]
}

module "terraform_ci_roles" {
  source = "../../modules/terraform-ci-roles"

  oidc_provider_arn    = aws_iam_openid_connect_provider.github.arn
  github_repository    = var.github_repository
  github_owner_id      = var.github_owner_id
  github_repository_id = var.github_repository_id
  apply_environment    = var.apply_environment
  state_bucket_name    = module.state_bucket.bucket_name
  managed_bucket_names = concat([var.log_bucket_name], [for s in values(var.sites) : s.bucket_name])
  hosted_zone_ids      = distinct([for s in values(var.sites) : s.zone_id])
}

module "deploy_role" {
  source   = "../../modules/github-deploy-role"
  for_each = { for site, s in var.sites : site => s if s.distribution_id != null }

  role_name            = "${replace(each.key, ".", "-")}-github-deploy"
  oidc_provider_arn    = aws_iam_openid_connect_provider.github.arn
  github_repository    = each.value.repository
  github_owner_id      = each.value.owner_id
  github_repository_id = each.value.repository_id
  github_environment   = each.value.deploy_environment
  deny_write_prefixes  = each.value.deny_write_prefixes
  bucket_arn           = "arn:${local.partition}:s3:::${each.value.bucket_name}"
  distribution_arn     = "arn:${local.partition}:cloudfront::${var.aws_account_id}:distribution/${each.value.distribution_id}"
}

# The key that signs the timetable manifest of a site that asks for it, and only the data role may use it.
module "manifest_key" {
  source   = "../../modules/manifest-signing-key"
  for_each = { for site, s in var.sites : site => s if s.sign_manifest }

  alias_name  = "${replace(each.key, ".", "-")}-manifest-signing"
  description = "Signs the timetable manifest (data/latest.json) of ${each.key}"

  # Only the data role signs; the key policy denies kms:Sign to every other principal. sign_manifest needs data_prefix, so the name exists.
  signer_role_arn = "arn:${local.partition}:iam::${var.aws_account_id}:role/${local.data_role_name[each.key]}"
}

# The second publisher of a site whose data is built on a schedule: main branch, one prefix, no invalidation.
# It exists as soon as the bucket name is known; it needs no distribution.
module "data_role" {
  source   = "../../modules/github-deploy-role"
  for_each = { for site, s in var.sites : site => s if s.data_prefix != null }

  role_name            = local.data_role_name[each.key]
  oidc_provider_arn    = aws_iam_openid_connect_provider.github.arn
  github_repository    = each.value.repository
  github_owner_id      = each.value.owner_id
  github_repository_id = each.value.repository_id
  bucket_arn           = "arn:${local.partition}:s3:::${each.value.bucket_name}"
  write_prefix         = each.value.data_prefix
  allow_read           = true
  allow_invalidation   = false
  sign_key_arn         = try(module.manifest_key[each.key].key_arn, null)
}

module "log_reader" {
  source = "../../modules/log-reader-role"

  role_name      = var.log_reader_role_name
  log_bucket_arn = "arn:${local.partition}:s3:::${var.log_bucket_name}"
  principal_arns = var.log_reader_principal_arns
}
