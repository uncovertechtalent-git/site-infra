# The public name. Off until attach_dns = true: the last step of the launch,
# after the site's privacy notice covers the server. Until then the endpoint
# answers on the distribution's own domain (dxxxx.cloudfront.net) only.

resource "aws_route53_record" "host" {
  for_each = var.attach_dns ? toset(["A", "AAAA"]) : toset([])

  zone_id = var.zone_id
  name    = var.host
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}
