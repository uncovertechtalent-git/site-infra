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

variable "tags" {
  description = "Tags for the roles, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
