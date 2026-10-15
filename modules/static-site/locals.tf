locals {
  name = replace(var.canonical_host, ".", "-")

  # Every host the certificate covers, from the start, so the cutover never waits on a new certificate.
  certificate_hosts = distinct(compact([var.canonical_host, var.www_host, var.test_host]))

  # Hosts attached to the distribution. Before stage 1 only the test host.
  canonical_hosts    = compact([var.canonical_host, var.www_host])
  distribution_hosts = distinct(concat(var.attach_canonical_hosts ? local.canonical_hosts : [], compact([var.test_host])))

  # Hosts that answer 301 to the canonical host.
  redirect_hosts = var.attach_canonical_hosts ? compact([var.www_host]) : []

  serve_from_cloudfront = var.dns_target == "cloudfront"

  log_prefix = "cloudfront/${var.canonical_host}"
}
