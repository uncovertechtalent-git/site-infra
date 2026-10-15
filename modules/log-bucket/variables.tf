variable "bucket_name" {
  description = "Name of the access log bucket. Keep the real name in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}

variable "retention_days" {
  description = "Days to keep an access log object. The stats job reads logs within minutes, so the raw logs only cover re-runs."
  type        = number
  default     = 30

  validation {
    condition     = var.retention_days >= 1 && var.retention_days <= 400
    error_message = "retention_days must be between 1 and 400."
  }
}

variable "tags" {
  description = "Tags for the bucket, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
