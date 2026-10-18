variable "role_name" {
  description = "Name of the execution role."
  type        = string
}

variable "function_name" {
  description = "Name of the function that runs as this role (for the description)."
  type        = string
}

variable "aws_account_id" {
  description = "Account whose Lambda service may assume the role."
  type        = string
}

variable "log_group_arn" {
  description = "ARN of the function's log group, without the trailing :*."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:logs:[a-z0-9-]+:[0-9]{12}:log-group:/aws/lambda/[A-Za-z0-9_-]+$", var.log_group_arn))
    error_message = "log_group_arn must be the ARN of one /aws/lambda/<function> log group, without a wildcard."
  }
}

variable "tags" {
  description = "Tags for the role, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
