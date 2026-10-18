variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for token.actions.githubusercontent.com."
  type        = string
}

variable "github_repository" {
  description = "Repository whose workflows assume the roles, as owner/name."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$", var.github_repository))
    error_message = "github_repository must be owner/name."
  }
}

variable "github_owner_id" {
  description = "Numeric id of the repository owner. With github_repository_id set, the trust policy matches GitHub's immutable subject (repo:owner@id/name@id), which a renamed or re-created repository cannot reuse. Null: the plain repo:owner/name subject."
  type        = number
  default     = null
}

variable "github_repository_id" {
  description = "Numeric id of the repository; see github_owner_id."
  type        = number
  default     = null

  validation {
    condition     = (var.github_repository_id == null) == (var.github_owner_id == null)
    error_message = "Set both github_owner_id and github_repository_id, or neither."
  }
}

variable "apply_environment" {
  description = "GitHub environment whose jobs may assume the apply role. Give it a required reviewer and limit it to main."
  type        = string
  default     = "production"
}

variable "role_name_prefix" {
  description = "Prefix of the two role names."
  type        = string
  default     = "site-infra"
}

variable "state_bucket_name" {
  description = "Bucket that holds the Terraform state."
  type        = string
}

variable "state_key_prefix" {
  description = "Key prefix of this repository's state files and tfvars in the state bucket."
  type        = string
  default     = "site-infra"
}

variable "protected_state_keys" {
  description = "State keys under the prefix that the apply role must never write (the bootstrap state)."
  type        = list(string)
  default     = ["bootstrap.tfstate"]
}

variable "managed_bucket_names" {
  description = "Buckets the shared and site stacks manage (log bucket, site buckets). The apply role writes these and no other bucket."
  type        = list(string)
}

variable "hosted_zone_ids" {
  description = "Route 53 zones whose records the site stacks manage."
  type        = list(string)
}

variable "functions" {
  description = "Lambda functions behind CloudFront that the apply role manages: each function's ARN, its execution role (bootstrap), its log group ARN without :*, and its CLOUDFRONT web ACL ARN up to the name (us-east-1, global/webacl/<name>; the role gets it with and without /<id>)."
  type = list(object({
    function_arn  = string
    role_arn      = string
    log_group_arn = string
    web_acl_arn   = string
  }))
  default = []

  validation {
    condition = alltrue([for f in var.functions :
      can(regex("^arn:[a-z-]+:lambda:[a-z0-9-]+:[0-9]{12}:function:[A-Za-z0-9_-]+$", f.function_arn)) &&
      can(regex("^arn:[a-z-]+:iam::[0-9]{12}:role/[A-Za-z0-9_+=,.@-]+$", f.role_arn)) &&
      can(regex("^arn:[a-z-]+:logs:[a-z0-9-]+:[0-9]{12}:log-group:/aws/lambda/[A-Za-z0-9_-]+$", f.log_group_arn)) &&
      can(regex("^arn:[a-z-]+:wafv2:us-east-1:[0-9]{12}:global/webacl/[A-Za-z0-9_-]+$", f.web_acl_arn))
    ])
    error_message = "Each function needs exact ARNs: no wildcard in the function, role, log group or web ACL (global/webacl/<name> in us-east-1)."
  }
}

variable "tags" {
  description = "Tags for the roles, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
