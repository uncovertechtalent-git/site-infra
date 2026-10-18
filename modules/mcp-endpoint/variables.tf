variable "name" {
  description = "Name of the function, its log group, the distribution's resources and the web ACL."
  type        = string

  validation {
    condition     = can(regex("^[a-z][a-z0-9-]{1,40}$", var.name))
    error_message = "name must be lower case letters, digits and dashes, 2 to 41 long."
  }
}

variable "host" {
  description = "Public host name of the endpoint, for example mcp.example.org."
  type        = string
}

variable "zone_id" {
  description = "Route 53 hosted zone that holds the host (certificate validation and, once attached, the alias records)."
  type        = string
}

variable "attach_dns" {
  description = "Create the A and AAAA alias records of the host. Until then the endpoint answers on the distribution's own domain only."
  type        = bool
  default     = false
}

variable "handler_file" {
  description = "Path of the function's single source file (handler.handler is the entry point)."
  type        = string
}

variable "package_dir" {
  description = "Directory for the built zip; outside the repository's tracked files."
  type        = string
}

variable "execution_role_arn" {
  description = "Role the function runs as (bootstrap stack): its own log group only."
  type        = string
}

variable "environment" {
  description = "Environment of the function, other than the origin secret."
  type        = map(string)
  default     = {}
}

variable "origin_secret" {
  description = "Value of the X-Origin-Verify header CloudFront adds; the function answers 403 without it. Set in local tfvars."
  type        = string
  sensitive   = true

  validation {
    condition     = length(var.origin_secret) >= 32 && can(regex("^[A-Za-z0-9_-]+$", var.origin_secret))
    error_message = "origin_secret must be at least 32 letters, digits, dashes or underscores (openssl rand -hex 32)."
  }
}

variable "memory_mb" {
  description = "Function memory (CPU scales with it)."
  type        = number
  default     = 512
}

variable "timeout_seconds" {
  description = "Function timeout."
  type        = number
  default     = 15
}

variable "reserved_concurrency" {
  description = "Most copies of the function that run at once: the hard ceiling on its cost and on its load on the site."
  type        = number
  default     = 5

  validation {
    condition     = var.reserved_concurrency >= 1 && var.reserved_concurrency <= 20
    error_message = "reserved_concurrency must be from 1 to 20."
  }
}

variable "log_retention_days" {
  description = "Retention of the function's log group (counts-only lines)."
  type        = number
  default     = 14
}

variable "rate_limit_per_5_minutes" {
  description = "Requests one IP address may send in 5 minutes before the web ACL blocks it with 429."
  type        = number
  default     = 300

  validation {
    condition     = var.rate_limit_per_5_minutes >= 10
    error_message = "rate_limit_per_5_minutes must be at least 10 (the WAF minimum)."
  }
}

variable "log_bucket_arn" {
  description = "ARN of the access log bucket (shared stack)."
  type        = string
}

variable "log_record_fields" {
  description = "CloudFront standard log (v2) fields to record: counts and latency only. Fields that identify a reader are refused."
  type        = list(string)
  default = [
    "date",
    "time",
    "x-edge-location",
    "cs-method",
    "cs-uri-stem",
    "sc-status",
    "sc-bytes",
    "time-taken",
    "time-to-first-byte",
    "x-edge-result-type",
    "x-edge-detailed-result-type",
    "cs-protocol-version",
  ]

  validation {
    condition = alltrue([
      for f in var.log_record_fields : !contains(["c-ip", "x-forwarded-for", "c-port", "cs(Cookie)", "cs-uri-query", "cs(User-Agent)", "cs(Referer)", "c-country", "x-edge-request-id"], f)
    ])
    error_message = "log_record_fields must not record c-ip, x-forwarded-for, c-port, cs(Cookie), cs-uri-query, cs(User-Agent), cs(Referer), c-country or x-edge-request-id."
  }
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"
}

variable "tags" {
  description = "Tags for the resources, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
