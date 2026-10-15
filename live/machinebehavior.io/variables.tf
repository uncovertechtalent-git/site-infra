variable "aws_account_id" {
  description = "The only AWS account this stack may change. Set in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be 12 digits."
  }
}

variable "region" {
  description = "Region of the site bucket."
  type        = string
  default     = "eu-central-1"
}

variable "zone_id" {
  description = "Route 53 hosted zone id of machinebehavior.io. Set in local tfvars."
  type        = string
}

variable "site_bucket_name" {
  description = "Name of the site bucket. Set in local tfvars."
  type        = string
}

variable "log_bucket_name" {
  description = "Name of the access log bucket (output of the shared stack). Set in local tfvars."
  type        = string
}

variable "attach_canonical_hosts" {
  description = "Cutover stage 1: attach machinebehavior.io and www to the distribution."
  type        = bool
  default     = false
}

variable "dns_target" {
  description = "Cutover stage 2: github_pages or cloudfront."
  type        = string
  default     = "github_pages"
}

variable "dns_ttl" {
  description = "TTL of the apex and www records while they hold plain values."
  type        = number
  default     = 300
}

variable "enable_github_deploy" {
  description = "Create the OIDC deploy role for the site repository. Needs enable_github_oidc in the shared stack."
  type        = bool
  default     = false
}

variable "github_repository" {
  description = "Repository whose main branch deploys the site."
  type        = string
  default     = "uncovertechtalent/machinebehavior.io"
}
