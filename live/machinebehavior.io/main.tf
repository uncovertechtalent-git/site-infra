# machinebehavior.io on S3 and CloudFront. Cutover stages (README, "Cutover"):
#   0. test host only:        attach_canonical_hosts = false, dns_target = "github_pages"
#   1. canonical hosts ready: attach_canonical_hosts = true,  dns_target = "github_pages"
#   2. switched:              attach_canonical_hosts = true,  dns_target = "cloudfront"
# Rollback from 2: dns_target = "github_pages". GitHub Pages stays deployed until it is retired.

locals {
  canonical_host = "machinebehavior.io"
}

data "aws_s3_bucket" "logs" {
  bucket = var.log_bucket_name
}

module "site" {
  source = "../../modules/static-site"

  canonical_host = local.canonical_host
  www_host       = "www.${local.canonical_host}"
  test_host      = "next.${local.canonical_host}"
  zone_id        = var.zone_id
  bucket_name    = var.site_bucket_name
  log_bucket_arn = data.aws_s3_bucket.logs.arn

  attach_canonical_hosts = var.attach_canonical_hosts
  dns_target             = var.dns_target
  dns_ttl                = var.dns_ttl
}

# The apex and www records predate this stack (GitHub Pages). Import them once;
# after that these blocks are no-ops.
import {
  to = module.site.aws_route53_record.canonical["A"]
  id = "${var.zone_id}_${local.canonical_host}_A"
}

import {
  to = module.site.aws_route53_record.canonical["AAAA"]
  id = "${var.zone_id}_${local.canonical_host}_AAAA"
}

import {
  to = module.site.aws_route53_record.www[0]
  id = "${var.zone_id}_www.${local.canonical_host}_CNAME"
}

data "aws_iam_openid_connect_provider" "github" {
  count = var.enable_github_deploy ? 1 : 0

  url = "https://token.actions.githubusercontent.com"
}

module "deploy_role" {
  source = "../../modules/github-deploy-role"
  count  = var.enable_github_deploy ? 1 : 0

  role_name         = "${replace(local.canonical_host, ".", "-")}-github-deploy"
  oidc_provider_arn = data.aws_iam_openid_connect_provider.github[0].arn
  github_repository = var.github_repository
  bucket_arn        = module.site.bucket_arn
  distribution_arn  = module.site.distribution_arn
}
