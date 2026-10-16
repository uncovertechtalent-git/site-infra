variable "account_id" {
  description = "Cloudflare account id. Keep it in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[0-9a-f]{32}$", var.account_id))
    error_message = "account_id must be a 32-character Cloudflare id."
  }
}

variable "name" {
  description = "Name of the Access application."
  type        = string
}

variable "hostnames" {
  description = "Hostnames the application covers; the first is its primary domain. Keep the list in local tfvars when the hosts should not be advertised."
  type        = list(string)

  validation {
    condition     = length(var.hostnames) > 0 && alltrue([for h in var.hostnames : can(regex("^[a-z0-9.-]+\\.[a-z]{2,}$", h))])
    error_message = "Name at least one hostname, without scheme or path."
  }
}

variable "allowed_emails" {
  description = "Email addresses the Allow policy lets in, one include rule each. Keep them in local tfvars."
  type        = list(string)

  validation {
    condition     = length(var.allowed_emails) > 0 && alltrue([for e in var.allowed_emails : can(regex("^[^@\\s]+@[^@\\s]+\\.[^@\\s]+$", e))])
    error_message = "Name at least one email address; an empty list would leave nobody, a wildcard is not accepted."
  }
}

variable "create_one_time_pin" {
  description = "Create the one-time PIN login method. Set false when the account already has an identity provider and pass its id in identity_provider_ids."
  type        = bool
  default     = true
}

variable "identity_provider_ids" {
  description = "Identity providers allowed on the application when create_one_time_pin is false."
  type        = list(string)
  default     = []

  validation {
    condition     = var.create_one_time_pin || length(var.identity_provider_ids) > 0
    error_message = "Without the one-time PIN, name at least one identity provider."
  }
}

variable "session_duration" {
  description = "How long an Access session lasts before the person logs in again."
  type        = string
  default     = "24h"
}
