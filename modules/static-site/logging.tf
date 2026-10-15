# Standard logging (v2): CloudFront delivers access logs through CloudWatch
# vended logs to the log bucket as gzipped JSON lines, one prefix per site.
# The delivery API lives in us-east-1; the bucket can be in any region.
# Only the fields in var.log_record_fields are recorded: no IP address, port,
# cookie or query string ever reaches the bucket.

resource "aws_cloudwatch_log_delivery_source" "this" {
  region = "us-east-1"

  name         = "${local.name}-access-logs"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.this.arn

  tags = var.tags
}

resource "aws_cloudwatch_log_delivery_destination" "this" {
  region = "us-east-1"

  name          = "${local.name}-access-logs"
  output_format = "json"

  delivery_destination_configuration {
    destination_resource_arn = "${var.log_bucket_arn}/${local.log_prefix}"
  }

  tags = var.tags
}

resource "aws_cloudwatch_log_delivery" "this" {
  region = "us-east-1"

  delivery_source_name     = aws_cloudwatch_log_delivery_source.this.name
  delivery_destination_arn = aws_cloudwatch_log_delivery_destination.this.arn
  record_fields            = var.log_record_fields

  s3_delivery_configuration {
    suffix_path                 = "{yyyy}/{MM}/{dd}/{HH}"
    enable_hive_compatible_path = false
  }

  tags = var.tags
}
