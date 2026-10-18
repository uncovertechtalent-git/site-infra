# CloudFront in front of the function URL: a certificate from ACM in us-east-1,
# no caching, every viewer header except Host forwarded, the secret origin
# header, security headers, and a WAF web ACL with a rate limit per IP.

locals {
  # Managed policy, id fixed by AWS.
  cache_policy_caching_disabled = "4135ea2d-6df8-44a3-9df3-4b5a84be39ad"

  function_url_host = trimsuffix(trimprefix(aws_lambda_function_url.this.function_url, "https://"), "/")
}

# Only the headers the server reads reach the function. The managed "all viewer"
# policy would also forward cookies, query strings and the CloudFront-Viewer-*
# headers (address, city, postal code, coordinates, ASN), none of which it needs.
# CloudFront adds X-Forwarded-For in any case; the function never reads or logs it.
resource "aws_cloudfront_origin_request_policy" "this" {
  name    = "${var.name}-origin"
  comment = "Headers the ${var.host} MCP server reads, nothing else"

  headers_config {
    header_behavior = "whitelist"

    headers {
      items = ["Accept", "Content-Type", "MCP-Protocol-Version", "Origin"]
    }
  }

  cookies_config {
    cookie_behavior = "none"
  }

  query_strings_config {
    query_string_behavior = "none"
  }
}

resource "aws_acm_certificate" "this" {
  region = "us-east-1"

  domain_name       = var.host
  validation_method = "DNS"

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

resource "aws_route53_record" "certificate_validation" {
  zone_id         = var.zone_id
  name            = one(aws_acm_certificate.this.domain_validation_options).resource_record_name
  type            = one(aws_acm_certificate.this.domain_validation_options).resource_record_type
  records         = [one(aws_acm_certificate.this.domain_validation_options).resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  region = "us-east-1"

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [aws_route53_record.certificate_validation.fqdn]
}

resource "aws_wafv2_web_acl" "this" {
  region = "us-east-1"

  name        = var.name
  description = "Rate limit per IP for ${var.host}"
  scope       = "CLOUDFRONT"

  default_action {
    allow {}
  }

  custom_response_body {
    key          = "rate-limited"
    content_type = "APPLICATION_JSON"
    content      = jsonencode({ error = "rate limited; try again in a few minutes" })
  }

  rule {
    name     = "rate-per-ip"
    priority = 1

    action {
      block {
        custom_response {
          response_code            = 429
          custom_response_body_key = "rate-limited"
        }
      }
    }

    statement {
      rate_based_statement {
        limit                 = var.rate_limit_per_5_minutes
        evaluation_window_sec = 300
        aggregate_key_type    = "IP"
      }
    }

    # Counts in CloudWatch metrics only. Sampled requests would keep IP addresses and headers for three hours.
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "${var.name}-rate-per-ip"
      sampled_requests_enabled   = false
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = var.name
    sampled_requests_enabled   = false
  }

  tags = var.tags
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name    = "${var.name}-headers"
  comment = "Security headers for ${var.host}"

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "DENY"
      override     = true
    }

    referrer_policy {
      referrer_policy = "no-referrer"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = 31536000
      include_subdomains         = false
      preload                    = false
      override                   = true
    }

    content_security_policy {
      content_security_policy = "default-src 'none'; frame-ancestors 'none'"
      override                = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled      = true
  comment      = var.host
  aliases      = [var.host]
  http_version = "http2and3"
  # IPv4 only: the WAF rate rule counts single addresses and cannot group an IPv6
  # /64, so one host could rotate addresses under it and use up the concurrency.
  is_ipv6_enabled = false
  price_class     = var.price_class
  web_acl_id      = aws_wafv2_web_acl.this.arn

  origin {
    origin_id   = "function-url"
    domain_name = local.function_url_host

    custom_origin_config {
      http_port              = 80
      https_port             = 443
      origin_protocol_policy = "https-only"
      origin_ssl_protocols   = ["TLSv1.2"]
      origin_read_timeout    = 30
    }

    custom_header {
      name  = "X-Origin-Verify"
      value = var.origin_secret
    }
  }

  default_cache_behavior {
    target_origin_id           = "function-url"
    viewer_protocol_policy     = "https-only"
    allowed_methods            = ["DELETE", "GET", "HEAD", "OPTIONS", "PATCH", "POST", "PUT"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = local.cache_policy_caching_disabled
    origin_request_policy_id   = aws_cloudfront_origin_request_policy.this.id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id
  }

  restrictions {
    geo_restriction {
      restriction_type = "none"
    }
  }

  viewer_certificate {
    acm_certificate_arn      = aws_acm_certificate_validation.this.certificate_arn
    ssl_support_method       = "sni-only"
    minimum_protocol_version = "TLSv1.2_2021"
  }

  tags = var.tags
}
