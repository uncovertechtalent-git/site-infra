# Unit tests with mocked providers: no credentials, no calls to AWS, no cost.
# They pin what the endpoint's privacy and abuse limits rest on.

mock_provider "aws" {
  mock_resource "aws_lambda_function_url" {
    defaults = {
      function_url = "https://abcdefghijklmnopqrstuvwxyz012345.lambda-url.eu-central-1.on.aws/"
    }
  }

  mock_resource "aws_acm_certificate" {
    defaults = {
      arn = "arn:aws:acm:us-east-1:123456789012:certificate/00000000-0000-0000-0000-000000000000"
      domain_validation_options = [
        { domain_name = "mcp.example.org", resource_record_name = "_a.mcp.example.org.", resource_record_type = "CNAME", resource_record_value = "_a.acm-validations.aws." },
      ]
    }
  }

  mock_resource "aws_wafv2_web_acl" {
    defaults = {
      arn = "arn:aws:wafv2:us-east-1:123456789012:global/webacl/ask-example/00000000-0000-0000-0000-000000000000"
    }
  }

  mock_resource "aws_cloudfront_distribution" {
    defaults = {
      arn            = "arn:aws:cloudfront::123456789012:distribution/EDFDVBD6EXAMPLE"
      domain_name    = "d111111abcdef8.cloudfront.net"
      hosted_zone_id = "Z2FDTNDATAQYW2"
    }
  }

  mock_resource "aws_cloudwatch_log_delivery_destination" {
    defaults = {
      arn = "arn:aws:logs:us-east-1:123456789012:delivery-destination:ask-example-access-logs"
    }
  }
}

mock_provider "archive" {}

variables {
  name               = "ask-example"
  host               = "mcp.example.org"
  zone_id            = "Z0000000000000000000"
  handler_file       = "handler.py"
  package_dir        = "/tmp"
  execution_role_arn = "arn:aws:iam::123456789012:role/ask-example-lambda"
  origin_secret      = "0123456789abcdef0123456789abcdef"
  log_bucket_arn     = "arn:aws:s3:::example-logs"
  environment        = { ASK_SITE = "https://example.org" }
}

run "defaults_hold_the_limits" {
  command = apply

  assert {
    condition     = aws_lambda_function.this.reserved_concurrent_executions == 5
    error_message = "reserved concurrency caps cost and load"
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["ORIGIN_SECRET"] == var.origin_secret && aws_lambda_function.this.environment[0].variables["ASK_SITE"] == "https://example.org"
    error_message = "the function gets the origin secret and its environment"
  }

  assert {
    condition     = aws_lambda_function_url.this.authorization_type == "NONE" && aws_lambda_permission.url.function_url_auth_type == "NONE" && aws_lambda_permission.invoke.invoked_via_function_url
    error_message = "the function URL is public and has both invoke statements"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).custom_header == toset([{ name = "X-Origin-Verify", value = var.origin_secret }])
    error_message = "CloudFront sends the secret origin header"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.origin).domain_name == "abcdefghijklmnopqrstuvwxyz012345.lambda-url.eu-central-1.on.aws"
    error_message = "the origin is the function URL host"
  }

  assert {
    condition     = aws_cloudfront_distribution.this.web_acl_id == aws_wafv2_web_acl.this.arn
    error_message = "the web ACL sits in front of the distribution"
  }

  assert {
    condition     = one(aws_cloudfront_distribution.this.default_cache_behavior).cache_policy_id == "4135ea2d-6df8-44a3-9df3-4b5a84be39ad" && one(aws_cloudfront_distribution.this.default_cache_behavior).viewer_protocol_policy == "https-only"
    error_message = "no caching, HTTPS only"
  }

  assert {
    condition     = one([for r in aws_wafv2_web_acl.this.rule : r.statement[0].rate_based_statement[0].limit if r.name == "rate-per-ip"]) == 300
    error_message = "300 requests per IP in 5 minutes"
  }

  assert {
    condition     = alltrue([for r in aws_wafv2_web_acl.this.rule : !r.visibility_config[0].sampled_requests_enabled]) && !aws_wafv2_web_acl.this.visibility_config[0].sampled_requests_enabled
    error_message = "no sampled requests: they would keep IP addresses"
  }

  assert {
    condition     = length(setintersection(toset(aws_cloudwatch_log_delivery.this.record_fields), toset(["c-ip", "x-forwarded-for", "c-port", "cs(User-Agent)", "cs(Referer)", "c-country", "cs-uri-query", "cs(Cookie)", "x-edge-request-id"]))) == 0
    error_message = "access logs keep counts and latency only"
  }

  assert {
    condition     = !contains(keys(aws_lambda_function.this.environment[0].variables), "ORIGIN_SECRET_PREVIOUS")
    error_message = "no second secret unless one rotates"
  }

  assert {
    condition     = length(aws_route53_record.host) == 0
    error_message = "no public DNS record until attach_dns"
  }

  assert {
    condition     = output.endpoint == "https://d111111abcdef8.cloudfront.net/mcp"
    error_message = "before attach_dns the endpoint is the distribution domain"
  }
}

run "rotation_passes_both_secrets" {
  command = plan

  variables {
    origin_secret_previous = "fedcba9876543210fedcba9876543210"
  }

  assert {
    condition     = aws_lambda_function.this.environment[0].variables["ORIGIN_SECRET_PREVIOUS"] == "fedcba9876543210fedcba9876543210"
    error_message = "while it rotates, the function accepts the old secret too"
  }
}

run "attach_dns_adds_the_alias_records" {
  command = plan

  variables {
    attach_dns = true
  }

  assert {
    condition     = length(aws_route53_record.host) == 2
    error_message = "A and AAAA alias records"
  }
}

run "identifying_log_fields_are_refused" {
  command = plan

  variables {
    log_record_fields = ["date", "c-ip"]
  }

  expect_failures = [var.log_record_fields]
}

run "a_short_origin_secret_is_refused" {
  command = plan

  variables {
    origin_secret = "short"
  }

  expect_failures = [var.origin_secret]
}

run "concurrency_must_be_capped" {
  command = plan

  variables {
    reserved_concurrency = 1000
  }

  expect_failures = [var.reserved_concurrency]
}
