# Read-only role for the stats job that ships the access logs to Loki:
# list the log bucket and read its objects, nothing else.

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "Reads CloudFront access logs for the site statistics job."
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { AWS = var.principal_arns }
        Action    = "sts:AssumeRole"
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  name = "read-access-logs"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListLogs"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.log_bucket_arn
      },
      {
        Sid      = "ReadLogObjects"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = "${var.log_bucket_arn}/*"
      },
    ]
  })
}
