# The two roles GitHub Actions uses to run Terraform for this repository,
# both assumed through GitHub OIDC (no stored key):
#
#   plan:  pull requests of the repository. Read-only: the state, the
#          resources the stacks manage, IAM metadata. Plans run with
#          -lock=false, so no write at all.
#   apply: jobs in one GitHub environment (required reviewer, main only).
#          Writes the resources of the shared and site stacks, and their
#          state. No IAM action at all, no write to the bootstrap state or the
#          tfvars, no change to the state bucket itself: IAM and the state
#          bucket belong to the bootstrap stack, which only the operator
#          applies (README, "Break-glass").
#
# Fork pull requests get no OIDC token from GitHub, so they cannot assume
# either role.

data "aws_partition" "current" {}

locals {
  partition        = data.aws_partition.current.partition
  token            = "token.actions.githubusercontent.com"
  state_bucket_arn = "arn:${local.partition}:s3:::${var.state_bucket_name}"
  state_prefix     = trim(var.state_key_prefix, "/")
  state_objects    = "${local.state_bucket_arn}/${local.state_prefix}/*"
  protected_objects = concat(
    [for k in var.protected_state_keys : "${local.state_bucket_arn}/${local.state_prefix}/${k}*"],
    ["${local.state_bucket_arn}/${local.state_prefix}/tfvars/*"],
  )
  bucket_arns = [for b in var.managed_bucket_names : "arn:${local.partition}:s3:::${b}"]
  zone_arns   = [for z in var.hosted_zone_ids : "arn:${local.partition}:route53:::hostedzone/${z}"]

  bucket_read_actions = [
    "s3:GetBucket*",
    "s3:GetLifecycleConfiguration",
    "s3:GetEncryptionConfiguration",
    "s3:GetAccelerateConfiguration",
    "s3:GetReplicationConfiguration",
  ]

  plan_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ListState"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = local.state_bucket_arn
        Condition = { StringLike = { "s3:prefix" = ["${local.state_prefix}/*"] } }
      },
      {
        Sid      = "ReadStateAndVariables"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = local.state_objects
      },
      {
        Sid      = "ReadBucketSettings"
        Effect   = "Allow"
        Action   = local.bucket_read_actions
        Resource = concat(local.bucket_arns, [local.state_bucket_arn])
      },
      {
        Sid    = "ReadServices"
        Effect = "Allow"
        Action = [
          "cloudfront:Get*",
          "cloudfront:List*",
          "cloudfront:Describe*",
          "acm:Describe*",
          "acm:List*",
          "acm:GetCertificate",
          "route53:Get*",
          "route53:List*",
          "logs:GetDelivery*",
          "logs:DescribeDeliver*",
          "logs:ListTagsForResource",
          "iam:Get*",
          "iam:List*",
        ]
        Resource = "*"
      },
    ]
  }

  apply_policy = {
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "ListState"
        Effect    = "Allow"
        Action    = "s3:ListBucket"
        Resource  = local.state_bucket_arn
        Condition = { StringLike = { "s3:prefix" = ["${local.state_prefix}/*"] } }
      },
      {
        Sid      = "ReadWriteStateAndLocks"
        Effect   = "Allow"
        Action   = ["s3:GetObject", "s3:PutObject", "s3:DeleteObject"]
        Resource = local.state_objects
      },
      {
        Sid      = "NeverTheBootstrapStateOrTheVariables"
        Effect   = "Deny"
        Action   = ["s3:PutObject", "s3:DeleteObject"]
        Resource = local.protected_objects
      },
      {
        Sid    = "NeverTheStateBucketItself"
        Effect = "Deny"
        Action = [
          "s3:PutBucket*",
          "s3:DeleteBucket*",
          "s3:PutLifecycleConfiguration",
          "s3:PutEncryptionConfiguration",
        ]
        Resource = local.state_bucket_arn
      },
      {
        Sid    = "ManagedBuckets"
        Effect = "Allow"
        Action = concat(local.bucket_read_actions, [
          "s3:CreateBucket",
          "s3:DeleteBucket*",
          "s3:PutBucket*",
          "s3:PutLifecycleConfiguration",
          "s3:PutEncryptionConfiguration",
          "s3:ListBucket",
        ])
        Resource = local.bucket_arns
      },
      {
        Sid    = "CloudFront"
        Effect = "Allow"
        Action = [
          "cloudfront:Get*",
          "cloudfront:List*",
          "cloudfront:Describe*",
          "cloudfront:CreateDistribution",
          "cloudfront:CreateDistributionWithTags",
          "cloudfront:UpdateDistribution",
          "cloudfront:DeleteDistribution",
          "cloudfront:CreateFunction",
          "cloudfront:UpdateFunction",
          "cloudfront:PublishFunction",
          "cloudfront:DeleteFunction",
          "cloudfront:CreateOriginAccessControl",
          "cloudfront:UpdateOriginAccessControl",
          "cloudfront:DeleteOriginAccessControl",
          "cloudfront:CreateResponseHeadersPolicy",
          "cloudfront:UpdateResponseHeadersPolicy",
          "cloudfront:DeleteResponseHeadersPolicy",
          "cloudfront:TagResource",
          "cloudfront:UntagResource",
          "cloudfront:AllowVendedLogsDeliveryForResource",
        ]
        Resource = "*"
      },
      {
        Sid    = "CertificatesInUsEast1"
        Effect = "Allow"
        Action = [
          "acm:RequestCertificate",
          "acm:DeleteCertificate",
          "acm:AddTagsToCertificate",
          "acm:RemoveTagsFromCertificate",
          "acm:Describe*",
          "acm:List*",
          "acm:GetCertificate",
        ]
        Resource  = "*"
        Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
      },
      {
        Sid      = "RecordsInTheSiteZones"
        Effect   = "Allow"
        Action   = ["route53:ChangeResourceRecordSets", "route53:ListResourceRecordSets", "route53:GetHostedZone", "route53:ListTagsForResource"]
        Resource = local.zone_arns
      },
      {
        Sid      = "Route53Changes"
        Effect   = "Allow"
        Action   = ["route53:GetChange", "route53:ListHostedZones", "route53:ListHostedZonesByName"]
        Resource = "*"
      },
      {
        Sid    = "LogDelivery"
        Effect = "Allow"
        Action = [
          "logs:PutDeliverySource",
          "logs:PutDeliveryDestination",
          "logs:CreateDelivery",
          "logs:UpdateDeliveryConfiguration",
          "logs:DeleteDelivery",
          "logs:DeleteDeliverySource",
          "logs:DeleteDeliveryDestination",
          "logs:GetDelivery*",
          "logs:DescribeDeliver*",
          "logs:TagResource",
          "logs:UntagResource",
          "logs:ListTagsForResource",
        ]
        Resource = "*"
      },
    ]
  }
}

resource "aws_iam_role" "plan" {
  name                 = "${var.role_name_prefix}-terraform-plan"
  description          = "Read-only Terraform plan for pull requests of ${var.github_repository}"
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
            "${local.token}:aud" = "sts.amazonaws.com"
            "${local.token}:sub" = "repo:${var.github_repository}:pull_request"
          }
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "plan" {
  name   = "terraform-plan-read-only"
  role   = aws_iam_role.plan.id
  policy = jsonencode(local.plan_policy)
}

resource "aws_iam_role" "apply" {
  name                 = "${var.role_name_prefix}-terraform-apply"
  description          = "Terraform apply for ${var.github_repository}, environment ${var.apply_environment} only"
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
            "${local.token}:aud" = "sts.amazonaws.com"
            "${local.token}:sub" = "repo:${var.github_repository}:environment:${var.apply_environment}"
          }
        }
      },
    ]
  })

  tags = var.tags
}

resource "aws_iam_role_policy" "apply" {
  name   = "terraform-apply-sites"
  role   = aws_iam_role.apply.id
  policy = jsonencode(local.apply_policy)
}
