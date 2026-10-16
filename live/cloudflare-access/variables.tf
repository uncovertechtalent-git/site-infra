variable "account_id" {
  description = "Cloudflare account id. Set in local tfvars."
  type        = string
}

variable "hostnames" {
  description = "Hostnames the tunnel publishes. Set in local tfvars."
  type        = list(string)
}

variable "allowed_emails" {
  description = "People allowed through Access. Set in local tfvars."
  type        = list(string)
}

variable "manage_organization" {
  description = "Create the Zero Trust organization (team domain) here. False when it was enabled in the dashboard."
  type        = bool
  default     = false
}

variable "team_name" {
  description = "Zero Trust team name: the login page is <team_name>.cloudflareaccess.com."
  type        = string
  default     = null

  validation {
    condition     = !var.manage_organization || var.team_name != null
    error_message = "manage_organization needs team_name."
  }
}

variable "organization_name" {
  description = "Display name of the Zero Trust organization."
  type        = string
  default     = "Access"
}
