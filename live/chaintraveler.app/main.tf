# chaintraveler.app: a free offline web app (uncovertechtalent-git/chain-traveler) on S3 and CloudFront.
# A new domain, so there is no GitHub Pages stage to cut over from: when the domain is ready the apex and
# www go straight to CloudFront. Until then (domain_ready = false) the distribution answers on its own
# cloudfront.net name, which is enough to deploy and test the app, and nothing waits for the registry.
#
# Two publishers write to the bucket, with separate roles (live/bootstrap):
#   the app shell (everything except data/), from the production environment of the app repository, after approval;
#   the timetable (data/), from the main branch, daily, without approval. Dated builds under data/<date>/ never
#   change; data/latest.json points the app at the newest one.

locals {
  canonical_host = "chaintraveler.app"

  # CloudFront managed cache policies (no IAM permission is needed to use them).
  caching_disabled  = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"
  caching_optimized = "658327ea-f89d-4fab-a63d-7e88639e58f6"

  # The app is one origin: its own scripts, styles, icon, manifest and service worker, fetches to itself, nothing
  # inline and nothing from elsewhere. Canvas drawing and element.style assignments need no allowance.
  content_security_policy = join("; ", [
    "default-src 'none'",
    "script-src 'self'",
    "style-src 'self'",
    "img-src 'self'",
    "connect-src 'self'",
    "manifest-src 'self'",
    "worker-src 'self'",
    "base-uri 'none'",
    "form-action 'none'",
    "frame-ancestors 'none'",
    "object-src 'none'",
  ])
}

data "aws_s3_bucket" "logs" {
  bucket = var.log_bucket_name
}

module "site" {
  source = "../../modules/static-site"

  canonical_host = local.canonical_host
  www_host       = "www.${local.canonical_host}"
  zone_id        = var.zone_id
  bucket_name    = var.site_bucket_name
  log_bucket_arn = data.aws_s3_bucket.logs.arn

  attach_canonical_hosts = true
  dns_target             = "cloudfront"
  dns_ttl                = var.dns_ttl
  custom_domain_ready    = var.domain_ready

  content_security_policy = local.content_security_policy

  # First match wins. The shell (everything else) takes the default behaviour: the objects carry no-cache, so a
  # browser revalidates and a deploy is visible at once (and the deploy invalidates the shell paths anyway).
  cache_rules = [
    {
      # The pointer to the newest timetable build: never cached at the edge, so a published build is current
      # at once and a rollback takes effect at once. The app also fetches it with cache: no-store.
      name            = "latest"
      path_pattern    = "/data/latest.json"
      cache_policy_id = local.caching_disabled
      cache_control   = "no-cache"
    },
    {
      # Dated builds, data/<date>/timetable.bin.gz and meta.json: published once, never changed.
      name            = "builds"
      path_pattern    = "/data/????-??-??/*"
      cache_policy_id = local.caching_optimized
      cache_control   = "public, max-age=31536000, immutable"
    },
  ]
}
