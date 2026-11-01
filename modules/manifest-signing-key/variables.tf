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
