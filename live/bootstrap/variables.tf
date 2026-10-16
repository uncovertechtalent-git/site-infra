variable "aws_account_id" {
  description = "The only AWS account this stack may change. Set in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be 12 digits."
  }
}

variable "region" {
  description = "Region of the state bucket."
  type        = string
  default     = "eu-central-1"
}

variable "state_bucket_name" {
  description = "Name of the state bucket. Set in local tfvars."
  type        = string
}

variable "operator_principal_arns" {
  description = "Break-glass principals (the operator host's IAM user). Only they write the bootstrap state and the tfvars. Set in local tfvars."
  type        = list(string)

  validation {
    condition     = length(var.operator_principal_arns) > 0
    error_message = "Name the operator, or nobody could write the bootstrap state."
  }
}

variable "github_repository" {
  description = "Repository whose Terraform workflow assumes the plan and apply roles."
  type        = string
  default     = "uncovertechtalent-git/site-infra"
}

variable "github_owner_id" {
  description = "Numeric id of the repository owner (public; GitHub's immutable OIDC subject uses it)."
  type        = number
  default     = 257729892
}

variable "github_repository_id" {
  description = "Numeric id of the repository (public; GitHub's immutable OIDC subject uses it)."
  type        = number
  default     = 1421056340
}

variable "apply_environment" {
  description = "GitHub environment whose jobs may assume the apply role."
  type        = string
  default     = "production"
}

variable "log_bucket_name" {
  description = "Name of the access log bucket (shared stack). Set in local tfvars."
  type        = string
}

variable "log_reader_role_name" {
  description = "Name of the stats job's read-only role. Set in local tfvars."
  type        = string
}

variable "log_reader_principal_arns" {
  description = "IAM principals that may assume the log reader role (the stats job's identity). Set in local tfvars."
  type        = list(string)
}

variable "sites" {
  description = "One entry per site, keyed by its canonical host: the site repository and its numeric owner and repository ids (GitHub's immutable OIDC subject), its bucket and zone, and its distribution once the site stack created it (null until then: no deploy role yet)."
  type = map(object({
    repository      = string
    owner_id        = number
    repository_id   = number
    bucket_name     = string
    zone_id         = string
    distribution_id = optional(string)
  }))
  default = {}
}
