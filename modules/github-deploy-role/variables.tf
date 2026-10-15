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
  description = "ARN of the CloudFront distribution the role may invalidate."
  type        = string
}

variable "tags" {
  description = "Tags for the role, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
