# IAM role that one GitHub Actions workflow assumes through OIDC to publish one
# site: sync the built files to the site bucket and invalidate the
# distribution. A site that has two publishers (its shell and its data) gets
# two roles from this module, each limited to its own part of the bucket by
# write_prefix and deny_write_prefixes. No long-lived key exists; GitHub stores no secret. The trust
# policy accepts tokens for one repository and one ref (or environment) only,
# so pull request runs and other branches cannot assume it.

locals {
  repository_parts = split("/", var.github_repository)
  subject_prefix = (var.github_repository_id == null ? "repo:${var.github_repository}" :
  "repo:${local.repository_parts[0]}@${var.github_owner_id}/${local.repository_parts[1]}@${var.github_repository_id}")
  subject = var.github_environment == null ? "${local.subject_prefix}:ref:${var.github_ref}" : "${local.subject_prefix}:environment:${var.github_environment}"
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

locals {
  object_arns = "${var.bucket_arn}/${var.write_prefix}*"

  policy_statements = concat(
    [
      {
        Sid      = "ListForSync"
        Effect   = "Allow"
        Action   = "s3:ListBucket"
        Resource = var.bucket_arn
        # A role limited to a prefix lists that prefix only.
        Condition = var.write_prefix == "" ? null : { StringLike = { "s3:prefix" = ["${var.write_prefix}*"] } }
      },
      {
        Sid      = "WriteSiteObjects"
        Effect   = "Allow"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = local.object_arns
      },
    ],
    var.allow_read ? [
      {
        Sid      = "ReadPublishedObjects"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = local.object_arns
      },
    ] : [],
    length(var.deny_write_prefixes) == 0 ? [] : [
      {
        Sid      = "NeverWriteElsewhere"
        Effect   = "Deny"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = [for p in var.deny_write_prefixes : "${var.bucket_arn}/${p}*"]
      },
    ],
    var.sign_key_arn == null ? [] : [
      {
        # Sign the manifest and have KMS check the signature before the pointer moves; read the public key to name the
        # key. Nothing that changes, disables or deletes the key: those are the operator's.
        Sid      = "SignManifest"
        Effect   = "Allow"
        Action   = ["kms:Sign", "kms:Verify", "kms:GetPublicKey"]
        Resource = var.sign_key_arn
      },
    ],
    var.allow_invalidation ? [
      {
        Sid      = "InvalidateCache"
        Effect   = "Allow"
        Action   = "cloudfront:CreateInvalidation"
        Resource = var.distribution_arn
      },
    ] : [],
  )
}

resource "aws_iam_role_policy" "this" {
  name = "publish-site"
  role = aws_iam_role.this.id
  policy = jsonencode({
    Version   = "2012-10-17"
    Statement = [for s in local.policy_statements : { for k, v in s : k => v if v != null }]
  })
}
