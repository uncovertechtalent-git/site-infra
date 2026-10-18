# The two roles GitHub Actions uses to run Terraform for this repository,
# both assumed through GitHub OIDC (no stored key):
#
#   plan:  pull requests of the repository. Read-only: the state, the
#          resources the stacks manage, IAM metadata. Plans run with
#          -lock=false, so no write at all.
#   apply: jobs in one GitHub environment (required reviewer, main only).
#          Writes the resources of the shared, site and function stacks, and
#          their state. No IAM action except iam:PassRole of the listed
#          function roles to Lambda; no write to the bootstrap state or the
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
  repository_parts = split("/", var.github_repository)
  subject_prefix = (var.github_repository_id == null ? "repo:${var.github_repository}" :
  "repo:${local.repository_parts[0]}@${var.github_owner_id}/${local.repository_parts[1]}@${var.github_repository_id}")
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
    Statement = concat([
      {
        Sid      = "ReadStateAndVariables"
        Effect   = "Allow"
        Action   = "s3:GetObject"
        Resource = local.state_objects
      },
      {
        # s3:ListBucket also covers HeadBucket, which the provider calls to find a
        # bucket. Without it the plan reads a bucket as gone and plans to re-create it.
        Sid      = "ReadBuckets"
        Effect   = "Allow"
        Action   = concat(local.bucket_read_actions, ["s3:ListBucket"])
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
    ], local.plan_function_statements)
  }

  apply_policy = {
    Version = "2012-10-17"
    Statement = concat([
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
    ], local.apply_function_statements)
  }

  # Functions behind CloudFront (var.functions, for example the MCP endpoint): the
  # function, its log group, its web ACL, and passing its one execution role to
  # Lambda. The apply role still cannot create, change or attach a role or a
  # policy; iam:PassRole names one role, which the bootstrap stack defines, and
  # only for the Lambda service.
  function_arns  = flatten([for f in var.functions : [f.function_arn, "${f.function_arn}:*"]])
  log_group_arns = flatten([for f in var.functions : [f.log_group_arn, "${f.log_group_arn}:*"]])
  web_acl_arns   = [for f in var.functions : f.web_acl_arn]

  plan_function_statements = length(var.functions) == 0 ? [] : [
    {
      Sid      = "ReadFunctions"
      Effect   = "Allow"
      Action   = ["lambda:Get*", "lambda:List*"]
      Resource = local.function_arns
    },
    {
      Sid      = "ReadWebAclsAndLogGroups"
      Effect   = "Allow"
      Action   = ["wafv2:Get*", "wafv2:List*", "logs:DescribeLogGroups", "logs:ListTagsLogGroup"]
      Resource = "*"
    },
  ]

  apply_function_statements = length(var.functions) == 0 ? [] : [
    {
      Sid    = "Functions"
      Effect = "Allow"
      Action = [
        "lambda:CreateFunction",
        "lambda:DeleteFunction*",
        "lambda:UpdateFunction*",
        "lambda:PutFunction*",
        "lambda:CreateFunctionUrlConfig",
        "lambda:AddPermission",
        "lambda:RemovePermission",
        "lambda:TagResource",
        "lambda:UntagResource",
        "lambda:Get*",
        "lambda:List*",
      ]
      Resource = local.function_arns
    },
    {
      Sid       = "PassTheFunctionRolesToLambdaOnly"
      Effect    = "Allow"
      Action    = "iam:PassRole"
      Resource  = [for f in var.functions : f.role_arn]
      Condition = { StringEquals = { "iam:PassedToService" = "lambda.amazonaws.com" } }
    },
    {
      Sid      = "FunctionLogGroups"
      Effect   = "Allow"
      Action   = ["logs:CreateLogGroup", "logs:DeleteLogGroup", "logs:PutRetentionPolicy", "logs:DeleteRetentionPolicy", "logs:TagLogGroup", "logs:UntagLogGroup", "logs:ListTagsLogGroup"]
      Resource = local.log_group_arns
    },
    {
      Sid      = "ListLogGroups"
      Effect   = "Allow"
      Action   = "logs:DescribeLogGroups"
      Resource = "*"
    },
    {
      Sid       = "FunctionWebAcls"
      Effect    = "Allow"
      Action    = ["wafv2:CreateWebACL", "wafv2:UpdateWebACL", "wafv2:DeleteWebACL", "wafv2:GetWebACL", "wafv2:TagResource", "wafv2:UntagResource", "wafv2:ListTagsForResource"]
      Resource  = local.web_acl_arns
      Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
    },
    {
      Sid       = "ListWebAcls"
      Effect    = "Allow"
      Action    = "wafv2:ListWebACLs"
      Resource  = "*"
      Condition = { StringEquals = { "aws:RequestedRegion" = "us-east-1" } }
    },
  ]
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
            "${local.token}:sub" = "${local.subject_prefix}:pull_request"
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
            "${local.token}:sub" = "${local.subject_prefix}:environment:${var.apply_environment}"
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
