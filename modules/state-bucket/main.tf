# S3 bucket for Terraform state. Locking uses the S3 lock file (backend setting
# use_lockfile = true), so no DynamoDB table. Versioning keeps every state
# revision; noncurrent revisions expire after var.noncurrent_version_days.
# The bucket policy backs up IAM: with writer_principal_arns set, nobody else
# writes or deletes an object, whatever IAM allows; keys in
# operator_only_keys are writable by operator_principal_arns alone.

resource "aws_s3_bucket" "this" {
  bucket = var.bucket_name

  tags = var.tags

  lifecycle {
    prevent_destroy = true
  }
}

resource "aws_s3_bucket_ownership_controls" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    object_ownership = "BucketOwnerEnforced"
  }
}

resource "aws_s3_bucket_public_access_block" "this" {
  bucket = aws_s3_bucket.this.id

  block_public_acls       = true
  block_public_policy     = true
  ignore_public_acls      = true
  restrict_public_buckets = true
}

resource "aws_s3_bucket_versioning" "this" {
  bucket = aws_s3_bucket.this.id

  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_server_side_encryption_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    apply_server_side_encryption_by_default {
      sse_algorithm = "AES256"
    }
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "this" {
  bucket = aws_s3_bucket.this.id

  rule {
    id     = "expire-old-state-revisions"
    status = "Enabled"

    filter {}

    noncurrent_version_expiration {
      noncurrent_days = var.noncurrent_version_days
    }

    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }

  depends_on = [aws_s3_bucket_versioning.this]
}

resource "aws_s3_bucket_policy" "this" {
  bucket = aws_s3_bucket.this.id
  policy = local.bucket_policy

  depends_on = [aws_s3_bucket_public_access_block.this]
}

locals {
  bucket_policy = jsonencode({
    Version = "2012-10-17"
    Statement = concat(
      [
        {
          Sid       = "DenyInsecureTransport"
          Effect    = "Deny"
          Principal = "*"
          Action    = "s3:*"
          Resource  = [aws_s3_bucket.this.arn, "${aws_s3_bucket.this.arn}/*"]
          Condition = { Bool = { "aws:SecureTransport" = "false" } }
        },
      ],
      length(var.writer_principal_arns) == 0 ? [] : [
        {
          Sid       = "OnlyNamedWriters"
          Effect    = "Deny"
          Principal = "*"
          Action    = ["s3:PutObject", "s3:DeleteObject"]
          Resource  = "${aws_s3_bucket.this.arn}/*"
          Condition = { ArnNotEquals = { "aws:PrincipalArn" = distinct(concat(var.writer_principal_arns, var.operator_principal_arns)) } }
        },
      ],
      length(var.operator_only_keys) == 0 ? [] : [
        {
          Sid       = "OperatorOnlyKeys"
          Effect    = "Deny"
          Principal = "*"
          Action    = ["s3:PutObject", "s3:DeleteObject"]
          Resource  = [for k in var.operator_only_keys : "${aws_s3_bucket.this.arn}/${k}"]
          Condition = { ArnNotEquals = { "aws:PrincipalArn" = var.operator_principal_arns } }
        },
      ],
    )
  })
}
