variable "role_name" {
  description = "Name of the reader role."
  type        = string
}

variable "log_bucket_arn" {
  description = "ARN of the access log bucket."
  type        = string
}

variable "principal_arns" {
  description = "IAM principals allowed to assume the role (the stats job's identity)."
  type        = list(string)

  validation {
    condition     = length(var.principal_arns) > 0
    error_message = "Name at least one principal."
  }
}

variable "tags" {
  description = "Tags for the role, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
