variable "bucket_name" {
  description = "Name of the state bucket. Bucket names are global; keep the real name in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}

variable "noncurrent_version_days" {
  description = "Days to keep a state revision after a newer one replaces it."
  type        = number
  default     = 90

  validation {
    condition     = var.noncurrent_version_days >= 7
    error_message = "Keep old state revisions for at least 7 days."
  }
}

variable "writer_principal_arns" {
  description = "Principals that may write and delete state objects (the CI apply role). Empty: IAM alone decides."
  type        = list(string)
  default     = []
}

variable "operator_principal_arns" {
  description = "Break-glass principals: they may write every object, operator_only_keys included."
  type        = list(string)
  default     = []
}

variable "operator_only_keys" {
  description = "Object key patterns only the operator may write (the bootstrap state, the tfvars)."
  type        = list(string)
  default     = []

  validation {
    condition     = length(var.operator_only_keys) == 0 || length(var.operator_principal_arns) > 0
    error_message = "operator_only_keys needs operator_principal_arns, or nobody could write those keys."
  }
}

variable "tags" {
  description = "Tags for the bucket, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
