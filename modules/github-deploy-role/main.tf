# IAM role that one GitHub Actions workflow assumes through OIDC to publish one
# site: sync the built files to the site bucket and invalidate the
# distribution. No long-lived key exists; GitHub stores no secret. The trust
# policy accepts tokens for one repository and one ref (or environment) only,
# so pull request runs and other branches cannot assume it.

locals {
  subject = var.github_environment == null ? "repo:${var.github_repository}:ref:${var.github_ref}" : "repo:${var.github_repository}:environment:${var.github_environment}"
}

resource "aws_iam_role" "this" {
  name                 = var.role_name
  description          = "GitHub Actions deploy of ${var.github_repository} to its site bucket"
  max_session_duration = 3600
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect    = "Allow"
        Principal = { Federated = var.oidc_provider_arn }
        Action    = "sts:AssumeRoleWithWebIdentity"
        Condition = {
          StringEquals = {
            "token.actions.githubusercontent.com:aud" = "sts.amazonaws.com"
            "token.actions.githubusercontent.com:sub" = local.subject
          }
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "this" {
  name = "publish-site"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid      = "ListForSync"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
      },
      {
        Sid      = "WriteSiteObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = "${var.bucket_arn}/*"
      },
      {
        Sid      = "InvalidateCache"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = var.distribution_arn
      },
    ]
  })
}
