# A public, read-only MCP server on Lambda behind CloudFront.
#
#   reader's MCP client -> CloudFront (TLS, WAF rate limit per IP) -> function URL -> Lambda
#
# The function URL has no IAM auth: origin access control for Lambda signs a
# POST only when the client sends the body's SHA-256 in x-amz-content-sha256,
# and MCP clients do not. CloudFront adds a secret header instead, and the
# function answers 403 without it, so the URL is useful only through
# CloudFront and its rate limit. Reserved concurrency caps cost and load.
# The function holds no data: it reads the site's published files over HTTPS.

locals {
  log_group  = "/aws/lambda/${var.name}"
  log_prefix = "cloudfront/${var.host}"
}

data "archive_file" "package" {
  type        = "zip"
  source_file = var.handler_file
  output_path = "${var.package_dir}/${var.name}.zip"
}

resource "aws_cloudwatch_log_group" "this" {
  name              = local.log_group
  retention_in_days = var.log_retention_days

  tags = var.tags
}

resource "aws_lambda_function" "this" {
  function_name                  = var.name
  description                    = "MCP server for ${var.host} (read-only)"
  role                           = var.execution_role_arn
  runtime                        = "python3.12" # the python3 of the CI runner image (ubuntu-24.04), where the tests run
  architectures                  = ["arm64"]
  handler                        = "handler.handler"
  filename                       = data.archive_file.package.output_path
  source_code_hash               = data.archive_file.package.output_base64sha256
  memory_size                    = var.memory_mb
  timeout                        = var.timeout_seconds
  reserved_concurrent_executions = var.reserved_concurrency

  environment {
    variables = merge(var.environment, { ORIGIN_SECRET = var.origin_secret },
    var.origin_secret_previous == "" ? {} : { ORIGIN_SECRET_PREVIOUS = var.origin_secret_previous })
  }

  logging_config {
    log_format = "Text"
    log_group  = aws_cloudwatch_log_group.this.name
  }

  tags = var.tags
}

# With auth NONE the provider adds the two resource-policy statements a public
# function URL needs (FunctionURLAllowPublicAccess for lambda:InvokeFunctionUrl,
# FunctionURLAllowInvokeAction for lambda:InvokeFunction via the URL; both
# strings are in provider 6.68.0), so this module declares no permission of its own.
resource "aws_lambda_function_url" "this" {
  function_name      = aws_lambda_function.this.function_name
  authorization_type = "NONE"
  invoke_mode        = "BUFFERED"
}
