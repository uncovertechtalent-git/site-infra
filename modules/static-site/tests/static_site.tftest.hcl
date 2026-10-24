# Unit tests with a mocked AWS provider: no credentials, no network calls to
# AWS, no cost. They pin the behaviour the cutover depends on.

mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn                         = "arn:aws:s3:::example-site"
      bucket_regional_domain_name = "example-site.s3.eu-central-1.amazonaws.com"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        { domain_name = "example.org", resource_record_name = "_a.example.org.", resource_record_type = "CNAME", resource_record_value = "_a.acm-validations.aws." },
        { domain_name = "www.example.org", resource_record_name = "_b.www.example.org.", resource_record_type = "CNAME", resource_record_value = "_b.acm-validations.aws." },
        { domain_name = "next.example.org", resource_record_name = "_c.next.example.org.", resource_record_type = "CNAME", resource_record_value = "_c.acm-validations.aws." },
      ]
    }
  }

  mock_resource "aws_cloudfront_function" {
    defaults = {
      arn = "arn:aws:cloudfront::123456789012:function/example-org-viewer-request"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_source" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-source:example-org-access-logs"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:example-org-access-logs"
    }
  }
}

variables {
  canonical_host = "example.org"
  www_host       = "www.example.org"
  test_host      = "next.example.org"
  zone_id        = "Z0000000000000000000"
  bucket_name    = "example-site"
  log_bucket_arn = "arn:aws:s3:::example-logs"
}

run "stage_0_serves_the_test_host_only" {
  command = plan

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["next.example.org"])
    error_message = "Before stage 1 only the test host is attached."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var REDIRECT_HOSTS = [];")
    error_message = "Before stage 1 no host redirects."
  }

  assert {
    condition     = aws_route53_record.canonical["A"].records == toset(var.github_pages.ipv4) && aws_route53_record.canonical["AAAA"].records == toset(var.github_pages.ipv6)
    error_message = "The apex records keep the GitHub Pages values."
  }

  assert {
    condition     = aws_route53_record.www[0].records == toset(["example.org"])
    error_message = "www is a CNAME to the apex, never into github.io (CAA)."
  }

  assert {
    condition     = aws_acm_certificate.this.subject_alternative_names == toset(["www.example.org", "next.example.org"])
    error_message = "The certificate covers every host from the start."
  }

  assert {
    condition     = length(aws_route53_record.certificate_validation) == 3
    error_message = "One validation record per certificate host."
  }
}

run "bucket_is_private" {
  command = plan

  assert {
    condition = alltrue([
      aws_s3_bucket_public_access_block.site.block_public_acls,
      aws_s3_bucket_public_access_block.site.block_public_policy,
      aws_s3_bucket_public_access_block.site.ignore_public_acls,
      aws_s3_bucket_public_access_block.site.restrict_public_buckets,
    ])
    error_message = "All four public access blocks are on."
  }

  assert {
    condition     = aws_s3_bucket_ownership_controls.site.rule[0].object_ownership == "BucketOwnerEnforced"
    error_message = "ACLs are disabled."
  }
}

run "only_the_distribution_reads_the_bucket" {
  command = apply

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.site.policy).Statement :
      s.Effect == "Allow" && s.Principal == { Service = "cloudfront.amazonaws.com" } && s.Action == "s3:GetObject" && s.Condition.StringEquals["AWS:SourceArn"] == "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
    ])
    error_message = "The bucket policy allows reads by this distribution through OAC."
  }

  assert {
    condition = length([
      for s in jsondecode(aws_s3_bucket_policy.site.policy).Statement : s if s.Effect == "Allow"
    ]) == 1
    error_message = "The bucket policy allows nothing else."
  }

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.site.policy).Statement :
      s.Effect == "Deny" && s.Condition.Bool["aws:SecureTransport"] == "false"
    ])
    error_message = "Plain HTTP requests to the bucket are denied."
  }
}

run "stage_1_attaches_the_canonical_hosts_without_dns_change" {
  command = plan

  variables {
    attach_canonical_hosts = true
  }

  assert {
    condition     = aws_cloudfront_distribution.this.aliases == toset(["example.org", "www.example.org", "next.example.org"])
    error_message = "Stage 1 attaches the apex and www hosts."
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var REDIRECT_HOSTS = [\"www.example.org\"];")
    error_message = "Stage 1 redirects www to the apex."
  }

  assert {
    condition     = aws_route53_record.canonical["A"].records == toset(var.github_pages.ipv4) && length(aws_route53_record.canonical["A"].alias) == 0
    error_message = "Stage 1 leaves DNS on GitHub Pages."
  }
}

run "stage_2_points_dns_at_cloudfront" {
  command = apply

  variables {
    attach_canonical_hosts = true
    dns_target             = "cloudfront"
  }

  assert {
    condition     = one(aws_route53_record.canonical["A"].alias).name == "d111111abcdef8.cloudfront.net" && one(aws_route53_record.canonical["AAAA"].alias).name == "d111111abcdef8.cloudfront.net"
    error_message = "Stage 2 aliases the apex A and AAAA records to the distribution."
  }

  assert {
    condition     = aws_route53_record.canonical["A"].records == null
    error_message = "Stage 2 drops the GitHub Pages addresses."
  }

  assert {
    condition     = aws_route53_record.www[0].records == toset(["example.org"])
    error_message = "In stage 2 www still follows the apex."
  }
}

run "dns_switch_needs_stage_1" {
  command = plan

  variables {
    dns_target = "cloudfront"
  }

  expect_failures = [var.dns_target]
}

run "logs_never_record_ip_addresses" {
  command = plan

  assert {
    condition     = length(setintersection(toset(aws_cloudwatch_log_delivery.this.record_fields), toset(["c-ip", "x-forwarded-for", "c-port", "cs(Cookie)", "cs-uri-query"]))) == 0
    error_message = "The default log fields carry no IP address, port, cookie or query string."
  }

  assert {
    condition     = aws_cloudwatch_log_delivery_destination.this.delivery_destination_configuration[0].destination_resource_arn == "arn:aws:s3:::example-logs/cloudfront/example.org"
    error_message = "Each site writes under its own prefix."
  }
}

run "ip_fields_are_refused" {
  command = plan

  variables {
    log_record_fields = ["date", "time", "c-ip"]
  }

  expect_failures = [var.log_record_fields]
}

run "security_headers" {
  command = plan

  assert {
    condition     = aws_cloudfront_response_headers_policy.this.security_headers_config[0].strict_transport_security[0].access_control_max_age_sec == 31536000
    error_message = "HSTS for one year."
  }

  assert {
    condition     = aws_cloudfront_distribution.this.viewer_certificate[0].minimum_protocol_version == "TLSv1.2_2021"
    error_message = "TLS 1.2 or later only."
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.default_cache_behavior).viewer_protocol_policy == "redirect-to-https"
    error_message = "Plain HTTP redirects to HTTPS."
  }
}

run "path_redirects_default_to_none" {
  command = plan

  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var PATH_REDIRECTS = {};")
    error_message = "With no path_redirects the function carries an empty table."
  }
}

run "path_redirects_render_into_the_function" {
  command = plan

  variables {
    path_redirects = {
      "/old/" = "/new/"
    }
  }

  assert {
    condition     = strcontains(aws_cloudfront_function.viewer_request.code, "var PATH_REDIRECTS = {\"/old/\":\"/new/\"};")
    error_message = "path_redirects render as a JSON table in the function."
  }
}

run "path_redirects_reject_unanchored_keys" {
  command = plan

  variables {
    path_redirects = {
      "old" = "/new/"
    }
  }

  expect_failures = [var.path_redirects]
}
