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

variable "tags" {
  description = "Tags for the bucket, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
