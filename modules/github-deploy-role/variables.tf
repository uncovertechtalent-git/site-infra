variable "role_name" {
  description = "Name of the deploy role."
  type        = string
}

variable "oidc_provider_arn" {
  description = "ARN of the IAM OIDC provider for token.actions.githubusercontent.com."
  type        = string
}

variable "github_repository" {
  description = "Repository allowed to assume the role, as owner/name."
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

variable "github_ref" {
  description = "Git ref allowed to assume the role, used when github_environment is null."
  type        = string
  default     = "refs/heads/main"

  validation {
    condition     = startswith(var.github_ref, "refs/")
    error_message = "github_ref must be a full ref such as refs/heads/main."
  }
}

variable "github_environment" {
  description = "GitHub environment allowed to assume the role. When set, it replaces the ref in the token subject."
  type        = string
  default     = null
}

variable "bucket_arn" {
  description = "ARN of the site bucket the role may write."
  type        = string
}

variable "distribution_arn" {
  description = "ARN of the CloudFront distribution the role may invalidate. Null when allow_invalidation is false."
  type        = string
  default     = null

  validation {
    condition     = !var.allow_invalidation || var.distribution_arn != null
    error_message = "distribution_arn is required while allow_invalidation is true."
  }
}

variable "allow_invalidation" {
  description = "Whether the role may create invalidations on distribution_arn. A role that only publishes data under immutable paths needs none."
  type        = bool
  default     = true
}

variable "write_prefix" {
  description = "Key prefix the role may list, write and delete, for example \"data/\". Empty: the whole bucket."
  type        = string
  default     = ""

  validation {
    condition     = var.write_prefix == "" || (endswith(var.write_prefix, "/") && !startswith(var.write_prefix, "/") && !strcontains(var.write_prefix, "*"))
    error_message = "write_prefix is empty or a key prefix that ends in \"/\", has no leading \"/\" and no wildcard."
  }
}

variable "deny_write_prefixes" {
  description = "Key prefixes the role may never write or delete, whatever else allows it (an explicit deny), for example [\"data/\"] for a role that publishes the site shell next to data published by another role."
  type        = list(string)
  default     = []

  validation {
    condition     = alltrue([for p in var.deny_write_prefixes : endswith(p, "/") && !startswith(p, "/") && !strcontains(p, "*")])
    error_message = "Each deny_write_prefixes entry ends in \"/\", has no leading \"/\" and no wildcard."
  }
}

variable "allow_read" {
  description = "Whether the role may read objects under write_prefix (s3:GetObject). A role that verifies what it published, or rolls a pointer back, needs it."
  type        = bool
  default     = false
}

variable "tags" {
  description = "Tags for the role, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
