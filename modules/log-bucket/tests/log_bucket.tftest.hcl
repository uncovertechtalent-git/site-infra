mock_provider "aws" {
  mock_resource "aws_s3_bucket" {
    defaults = {
      arn = "arn:aws:s3:::example-logs"
    }
  }

  mock_data "aws_caller_identity" {
    defaults = {
      account_id = "123456789012"
    }
  }

  mock_data "aws_partition" {
    defaults = {
      partition = "aws"
    }
  }
}

variables {
  bucket_name = "example-logs"
}

run "only_cloudfront_log_delivery_from_this_account_writes" {
  command = apply

  assert {
    condition = anytrue([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement :
      s.Effect == "Allow"
      && s.Principal == { Service = "delivery.logs.amazonaws.com" }
      && s.Action == "s3:PutObject"
      && s.Condition.StringEquals["aws:SourceAccount"] == "123456789012"
      && s.Condition.ArnLike["aws:SourceArn"] == "arn:aws:logs:us-east-1:123456789012:delivery-source:*"
    ])
    error_message = "Log delivery writes are scoped to delivery sources in this account."
  }

  assert {
    condition = length([
      for s in jsondecode(aws_s3_bucket_policy.this.policy).Statement : s if s.Effect == "Allow"
    ]) == 1
    error_message = "The bucket policy allows nothing else."
  }

  assert {
    condition     = aws_s3_bucket_lifecycle_configuration.this.rule[0].expiration[0].days == 30
    error_message = "Raw access logs expire after 30 days by default."
  }
}
