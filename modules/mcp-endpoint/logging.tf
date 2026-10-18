# Standard logging (v2) to the shared log bucket, like the sites: counts and
# latency only (var.log_record_fields). No IP address, port, User-Agent,
# referrer, country, cookie or query string reaches the bucket. Request bodies,
# where the questions are, are never logged by CloudFront.

resource "aws_cloudwatch_log_delivery_source" "this" {
  region = "us-east-1"

  name         = "${var.name}-access-logs"
  log_type     = "ACCESS_LOGS"
  resource_arn = aws_cloudfront_distribution.this.arn

  tags = var.tags
}

resource "aws_cloudwatch_log_delivery_destination" "this" {
  region = "us-east-1"

  name          = "${var.name}-access-logs"
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
