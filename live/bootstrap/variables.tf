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
  description = <<-EOT
    One entry per site, keyed by its canonical host: the site repository and its numeric owner and repository ids
    (GitHub's immutable OIDC subject), its bucket and zone, and its distribution once the site stack created it
    (null until then: no deploy role yet).

    Optional, for a site whose shell and data have different publishers:
    - deploy_environment: the deploy role trusts this GitHub environment of the repository (for example
      "production", which needs a reviewer) instead of the main branch.
    - deny_write_prefixes: key prefixes the deploy role may never write (for example ["data/"]).
    - data_prefix: a second role, "<site>-github-data", that trusts the main branch (so a scheduled job needs no
      approval), may read, write and delete only under this prefix (for example "data/") and cannot invalidate.
    - sign_manifest: needs data_prefix. Creates an asymmetric KMS key that signs the site's timetable manifest and
      lets the data role (and only it) sign, verify and read the public key. Asymmetric keys do not rotate by
      themselves: to rotate, set it for a second key name by hand (README of the app, "Signed manifest").
  EOT
  type = map(object({
    repository          = string
    owner_id            = number
    repository_id       = number
    bucket_name         = string
    zone_id             = string
    distribution_id     = optional(string)
    deploy_environment  = optional(string)
    deny_write_prefixes = optional(list(string), [])
    data_prefix         = optional(string)
    sign_manifest       = optional(bool, false)
  }))
  default = {}

  validation {
    condition     = alltrue([for s in values(var.sites) : !s.sign_manifest || s.data_prefix != null])
    error_message = "sign_manifest needs data_prefix: the data role is the one that signs."
  }
}
