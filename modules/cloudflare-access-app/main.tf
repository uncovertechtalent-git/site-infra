# Cloudflare Access in front of a set of hostnames: one self-hosted
# application, one reusable Allow policy that names each allowed email, and
# the one-time PIN login method (Cloudflare mails a code to the address; no
# identity provider needed). Anyone else gets the Access login page and no
# code. The origin stays reachable only through the tunnel; this module does
# not touch DNS or the tunnel.

resource "cloudflare_zero_trust_access_identity_provider" "otp" {
  count = var.create_one_time_pin ? 1 : 0

  account_id = var.account_id
  name       = "One-time PIN"
  type       = "onetimepin"
  config     = {}
}

locals {
  identity_provider_ids = var.create_one_time_pin ? [cloudflare_zero_trust_access_identity_provider.otp[0].id] : var.identity_provider_ids
}

resource "cloudflare_zero_trust_access_policy" "allow" {
  account_id       = var.account_id
  name             = "${var.name}: allowed people"
  decision         = "allow"
  session_duration = var.session_duration
  include          = [for e in var.allowed_emails : { email = { email = e } }]
}

resource "cloudflare_zero_trust_access_application" "this" {
  account_id = var.account_id
  name       = var.name
  type       = "self_hosted"
  domain     = var.hostnames[0]
  destinations = [for h in var.hostnames : {
    type = "public"
    uri  = h
  }]

  allowed_idps               = local.identity_provider_ids
  auto_redirect_to_identity  = length(local.identity_provider_ids) == 1
  session_duration           = var.session_duration
  app_launcher_visible       = false
  http_only_cookie_attribute = true
  same_site_cookie_attribute = "lax"

  policies = [{
    id         = cloudflare_zero_trust_access_policy.allow.id
    precedence = 1
  }]
}
