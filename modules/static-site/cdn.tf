# CloudFront in front of the private bucket: origin access control, a viewer
# request function for redirects and index documents, a response headers
# policy with the security headers, and a certificate from ACM in us-east-1
# (the only region CloudFront takes certificates from).

resource "aws_acm_certificate" "this" {
  region = "us-east-1"

  domain_name               = var.canonical_host
  subject_alternative_names = [for h in local.certificate_hosts : h if h != var.canonical_host]
  validation_method         = "DNS"

  tags = var.tags

  lifecycle {
    create_before_destroy = true
  }
}

locals {
  # Keyed by host name from the configuration, so the keys are known at plan time.
  certificate_validation = {
    for o in aws_acm_certificate.this.domain_validation_options : o.domain_name => o
  }
}

resource "aws_route53_record" "certificate_validation" {
  for_each = toset(local.certificate_hosts)

  zone_id         = var.zone_id
  name            = local.certificate_validation[each.key].resource_record_name
  type            = local.certificate_validation[each.key].resource_record_type
  records         = [local.certificate_validation[each.key].resource_record_value]
  ttl             = 300
  allow_overwrite = true
}

resource "aws_acm_certificate_validation" "this" {
  region = "us-east-1"

  certificate_arn         = aws_acm_certificate.this.arn
  validation_record_fqdns = [for r in aws_route53_record.certificate_validation : r.fqdn]
}

resource "aws_cloudfront_origin_access_control" "this" {
  name                              = local.name
  description                       = "Signed reads of the ${var.canonical_host} site bucket"
  origin_access_control_origin_type = "s3"
  signing_behavior                  = "always"
  signing_protocol                  = "sigv4"
}

resource "aws_cloudfront_function" "viewer_request" {
  name    = "${local.name}-viewer-request"
  comment = "Redirects and index documents for ${var.canonical_host}"
  runtime = "cloudfront-js-2.0"
  publish = true
  code = templatefile("${path.module}/functions/viewer-request.js.tftpl", {
    canonical_host = var.canonical_host
    redirect_hosts = local.redirect_hosts
    path_redirects = var.path_redirects
  })
}

resource "aws_cloudfront_response_headers_policy" "this" {
  name    = "${local.name}-headers"
  comment = "Security headers for ${var.canonical_host}"

  # GitHub Pages answers every request with Access-Control-Allow-Origin: *.
  # CloudFront adds it to cross-origin requests, the ones that need it.
  cors_config {
    access_control_allow_credentials = false
    access_control_max_age_sec       = 600
    origin_override                  = true

    access_control_allow_headers {
      items = ["*"]
    }

    access_control_allow_methods {
      items = ["GET", "HEAD", "OPTIONS"]
    }

    access_control_allow_origins {
      items = ["*"]
    }
  }

  security_headers_config {
    content_type_options {
      override = true
    }

    frame_options {
      frame_option = "SAMEORIGIN"
      override     = true
    }

    referrer_policy {
      referrer_policy = "strict-origin-when-cross-origin"
      override        = true
    }

    strict_transport_security {
      access_control_max_age_sec = var.hsts_max_age_seconds
      include_subdomains         = true
      preload                    = false
      override                   = true
    }

    dynamic "content_security_policy" {
      for_each = var.content_security_policy == null ? [] : [var.content_security_policy]

      content {
        content_security_policy = content_security_policy.value
        override                = true
      }
    }
  }

  custom_headers_config {
    items {
      header   = "Permissions-Policy"
      value    = var.permissions_policy
      override = true
    }
  }
}

resource "aws_cloudfront_distribution" "this" {
  enabled             = true
  comment             = var.canonical_host
  aliases             = local.distribution_hosts
  default_root_object = "index.html"
  http_version        = "http2and3"
  is_ipv6_enabled     = true
  price_class         = var.price_class

  origin {
    origin_id                = "site-bucket"
    domain_name              = aws_s3_bucket.site.bucket_regional_domain_name
    origin_access_control_id = aws_cloudfront_origin_access_control.this.id
  }

  default_cache_behavior {
    target_origin_id           = "site-bucket"
    viewer_protocol_policy     = "redirect-to-https"
    allowed_methods            = ["GET", "HEAD", "OPTIONS"]
    cached_methods             = ["GET", "HEAD"]
    compress                   = true
    cache_policy_id            = var.cache_policy_id
    response_headers_policy_id = aws_cloudfront_response_headers_policy.this.id

    function_association {
      event_type   = "viewer-request"
      function_arn = aws_cloudfront_function.viewer_request.arn
    }
  }

  # OAC has no s3:ListBucket, so S3 answers a missing key with 403. Both serve the site's 404 page.
  custom_error_response {
    error_code            = 403
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
  }

  custom_error_response {
    error_code            = 404
    response_code         = 404
    response_page_path    = "/404.html"
    error_caching_min_ttl = 60
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
