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

  # ADR-0038 URL moves in the machinebehavior.io repo (site/redirects.yml). Prefix rules,
  # so markdown twins, data files and sub-pages follow their page. Article and
  # case-file entries are permanent: never remove them.
  path_redirects = {
    "/continuous-conformity/"                 = "/conformity/standard/"
    "/continuous-conformity-self-assessment/" = "/conformity/self-assessment/"
    "/claims/"                                = "/research/claims/"
    "/experiments/"                           = "/research/experiments/"
    "/objections/"                            = "/research/objections/"
    "/evidence/"                              = "/research/evidence/"
    "/slips/"                                 = "/research/slips/"
    "/terms/"                                 = "/research/terms/"
    "/red-team/"                              = "/research/red-team/"
    "/the-cheating-moved/"                    = "/research/articles/the-cheating-moved/"
    "/chaos-engineering-for-behaviour/"       = "/research/articles/chaos-engineering-for-behaviour/"
    "/running-conjobs-for-ai/"                = "/research/case-files/running-conjobs-for-ai/"
    "/case-12-licence-rule-mid-task/"         = "/research/case-files/case-12-licence-rule-mid-task/"
  }
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
