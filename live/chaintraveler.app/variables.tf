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
  description = "Route 53 hosted zone id of chaintraveler.app (created by the domain registration). Set in local tfvars."
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

variable "domain_ready" {
  description = "false: the distribution answers on its cloudfront.net name only, and nothing waits for the registry. true: the certificate is validated, chaintraveler.app and www are attached, and DNS points at CloudFront. Set it to true once the registration is SUCCESSFUL and the registry delegates to the zone (docs/chaintraveler.app.md, step 6)."
  type        = bool
  default     = false
}

variable "dns_ttl" {
  description = "TTL of the www record."
  type        = number
  default     = 300
}
