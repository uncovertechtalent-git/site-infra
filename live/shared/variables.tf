variable "aws_account_id" {
  description = "The only AWS account this stack may change. Set in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be 12 digits."
  }
}

variable "region" {
  description = "Region of the log bucket."
  type        = string
  default     = "eu-central-1"
}

variable "log_bucket_name" {
  description = "Name of the access log bucket. Set in local tfvars."
  type        = string
}

variable "log_retention_days" {
  description = "Days to keep raw access logs."
  type        = number
  default     = 30
}

variable "log_reader_principal_arns" {
  description = "IAM principals that may assume the log reader role (the stats job's identity). Set in local tfvars."
  type        = list(string)
  default     = []
}

variable "enable_github_oidc" {
  description = "Create the IAM OIDC provider for GitHub Actions."
  type        = bool
  default     = false
}
