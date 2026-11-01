variable "alias_name" {
  description = "Alias of the key without the alias/ prefix, for example chaintraveler-app-manifest-signing."
  type        = string

  validation {
    condition     = can(regex("^[A-Za-z0-9/_-]{1,200}$", var.alias_name)) && !startswith(var.alias_name, "aws/")
    error_message = "alias_name is letters, digits, / _ - only, and not under aws/."
  }
}

variable "description" {
  description = "What the key is for, shown in the console."
  type        = string
}

variable "signer_role_arn" {
  description = "ARN of the one role that may sign with the key: the data role of the site, as a string (arn:aws:iam::<account>:role/<name>), not a reference to the role. Everyone else is denied kms:Sign by the key policy; the account root keeps kms:*."
  type        = string

  validation {
    condition     = can(regex("^arn:[a-z-]+:iam::[0-9]{12}:role/[A-Za-z0-9+=,.@_/-]+$", var.signer_role_arn))
    error_message = "signer_role_arn is the ARN of an IAM role: arn:<partition>:iam::<12-digit account>:role/<name>."
  }
}

variable "deletion_window_in_days" {
  description = "Days between a delete request and the key's end (7 to 30). A signing key cannot be recovered, only kept."
  type        = number
  default     = 30

  validation {
    condition     = var.deletion_window_in_days >= 7 && var.deletion_window_in_days <= 30
    error_message = "deletion_window_in_days must be 7 to 30."
  }
}

variable "tags" {
  description = "Tags for the key, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
