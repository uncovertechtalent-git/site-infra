variable "aws_account_id" {
  description = "The only AWS account this stack may change. Set in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[0-9]{12}$", var.aws_account_id))
    error_message = "aws_account_id must be 12 digits."
  }
}

variable "region" {
  description = "Region of the function."
  type        = string
  default     = "eu-central-1"
}

variable "zone_id" {
  description = "Route 53 hosted zone id of machinebehavior.io. Set in local tfvars."
  type        = string
}

variable "log_bucket_name" {
  description = "Name of the access log bucket (output of the shared stack). Set in local tfvars."
  type        = string
}

variable "origin_secret" {
  description = "Secret header value between CloudFront and the function (openssl rand -hex 32). Set in local tfvars."
  type        = string
  sensitive   = true
}

variable "origin_secret_previous" {
  description = "The old origin secret while it rotates; empty otherwise. Set in local tfvars."
  type        = string
  default     = ""
  sensitive   = true
}

variable "attach_dns" {
  description = "Launch switch: the A and AAAA records of mcp.machinebehavior.io. Only after the site's privacy notice covers the server, on Stefan Coetzee's go."
  type        = bool
  default     = false
}
