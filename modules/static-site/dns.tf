# DNS for the site. The test host points at CloudFront from the start. The
# canonical (apex) records hold the GitHub Pages addresses until
# dns_target = cloudfront; the switch is an in-place update of the same
# records, and setting dns_target back to github_pages rolls it back.
# www is a CNAME to the apex in every stage, so it follows the apex. It must
# not point into github.io: github.io publishes CAA records that do not allow
# Amazon, and ACM then refuses the certificate for www (CAA_ERROR).
# Import the existing apex and www records before the first apply (see the
# import blocks in the root stack).

resource "aws_route53_record" "test" {
  for_each = var.test_host == null ? toset([]) : toset(["A", "AAAA"])

  zone_id = var.zone_id
  name    = var.test_host
  type    = each.key

  alias {
    name                   = aws_cloudfront_distribution.this.domain_name
    zone_id                = aws_cloudfront_distribution.this.hosted_zone_id
    evaluate_target_health = false
  }
}

resource "aws_route53_record" "canonical" {
  for_each = toset(["A", "AAAA"])

  zone_id = var.zone_id
  name    = var.canonical_host
  type    = each.key
  ttl     = local.serve_from_cloudfront ? null : var.dns_ttl
  records = local.serve_from_cloudfront ? null : (each.key == "A" ? var.github_pages.ipv4 : var.github_pages.ipv6)

  dynamic "alias" {
    for_each = local.serve_from_cloudfront ? [aws_cloudfront_distribution.this] : []

    content {
      name                   = alias.value.domain_name
      zone_id                = alias.value.hosted_zone_id
      evaluate_target_health = false
    }
  }
}

resource "aws_route53_record" "www" {
  count = var.www_host == null ? 0 : 1

  zone_id = var.zone_id
  name    = var.www_host
  type    = "CNAME"
  ttl     = var.dns_ttl
  records = [var.canonical_host]
}
