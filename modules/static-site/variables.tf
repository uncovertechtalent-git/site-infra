variable "canonical_host" {
  description = "Host name readers should end up on, for example example.org. Canonical tags on the site point here."
  type        = string
}

variable "www_host" {
  description = "Host that is a CNAME to the canonical host and, once attach_canonical_hosts is true, answers 301 to it from CloudFront. Null: no www host."
  type        = string
  default     = null
}

variable "test_host" {
  description = "Extra host that serves the site from day one, for parity checks before the cutover. Null: none."
  type        = string
  default     = null
}

variable "zone_id" {
  description = "Route 53 hosted zone that holds canonical_host. Keep the id in local tfvars."
  type        = string
}

variable "bucket_name" {
  description = "Name of the private bucket that holds the built site. Keep the real name in local tfvars."
  type        = string

  validation {
    condition     = can(regex("^[a-z0-9][a-z0-9.-]{1,61}[a-z0-9]$", var.bucket_name))
    error_message = "bucket_name must be a valid S3 bucket name."
  }
}

variable "attach_canonical_hosts" {
  description = "Stage 1 of the cutover: attach the canonical and www hosts to the distribution. DNS does not change."
  type        = bool
  default     = false
}

variable "dns_target" {
  description = "Stage 2 of the cutover: where the canonical (apex) records point. github_pages keeps the old addresses, cloudfront switches them. www follows the apex."
  type        = string
  default     = "github_pages"

  validation {
    condition     = contains(["github_pages", "cloudfront"], var.dns_target)
    error_message = "dns_target must be github_pages or cloudfront."
  }

  validation {
    condition     = var.dns_target == "github_pages" || var.attach_canonical_hosts
    error_message = "dns_target = cloudfront needs attach_canonical_hosts = true first."
  }
}

variable "dns_ttl" {
  description = "TTL in seconds of the apex records while they hold plain addresses, and of the www CNAME. Lower it a day before the cutover."
  type        = number
  default     = 300

  validation {
    condition     = var.dns_ttl >= 60 && var.dns_ttl <= 86400
    error_message = "dns_ttl must be between 60 and 86400."
  }
}

variable "github_pages" {
  description = "The GitHub Pages addresses of the apex, used while dns_target is github_pages and to roll back."
  type = object({
    ipv4 = list(string)
    ipv6 = list(string)
  })
  default = {
    ipv4 = ["185.199.108.153", "185.199.109.153", "185.199.110.153", "185.199.111.153"]
    ipv6 = ["2606:50c0:8000::153", "2606:50c0:8001::153", "2606:50c0:8002::153", "2606:50c0:8003::153"]
  }
}

variable "price_class" {
  description = "CloudFront price class."
  type        = string
  default     = "PriceClass_100"

  validation {
    condition     = contains(["PriceClass_100", "PriceClass_200", "PriceClass_All"], var.price_class)
    error_message = "price_class must be PriceClass_100, PriceClass_200 or PriceClass_All."
  }
}

variable "cache_policy_id" {
  description = "CloudFront cache policy for the default behaviour. Default: the managed CachingOptimized policy, which follows the Cache-Control of each object."
  type        = string
  default     = "658327ea-f89d-4fab-a63d-7e88639e58f6"
}

variable "hsts_max_age_seconds" {
  description = "Strict-Transport-Security max-age."
  type        = number
  default     = 31536000
}

variable "content_security_policy" {
  description = "Content-Security-Policy header value. Null: no header."
  type        = string
  default     = null
}

variable "permissions_policy" {
  description = "Permissions-Policy header value."
  type        = string
  default     = "camera=(), microphone=(), geolocation=(), payment=(), usb=()"
}

variable "log_bucket_arn" {
  description = "ARN of the access log bucket (module log-bucket)."
  type        = string
}

variable "log_record_fields" {
  description = "CloudFront standard log (v2) fields to record. Fields that carry the viewer IP address, port, cookies or query string are refused."
  type        = list(string)
  default = [
    "date",
    "time",
    "x-edge-location",
    "sc-bytes",
    "cs-method",
    "x-host-header",
    "cs-uri-stem",
    "sc-status",
    "cs(Referer)",
    "cs(User-Agent)",
    "x-edge-result-type",
    "x-edge-request-id",
    "cs-protocol",
    "time-taken",
    "x-edge-response-result-type",
    "cs-protocol-version",
    "time-to-first-byte",
    "x-edge-detailed-result-type",
    "sc-content-type",
    "c-country",
  ]

  validation {
    condition = alltrue([
      for f in var.log_record_fields : !contains(["c-ip", "x-forwarded-for", "c-port", "cs(Cookie)", "cs-uri-query"], f)
    ])
    error_message = "log_record_fields must not record c-ip, x-forwarded-for, c-port, cs(Cookie) or cs-uri-query."
  }
}

variable "path_redirects" {
  description = "Start-anchored path prefix redirects: a request whose path starts with a key answers 301 to the value plus the rest of the path. Keys and values start and end with \"/\". Longest key wins."
  type        = map(string)
  default     = {}

  validation {
    condition = alltrue([
      for k, v in var.path_redirects : startswith(k, "/") && endswith(k, "/") && startswith(v, "/") && endswith(v, "/") && k != "/"
    ])
    error_message = "path_redirects keys and values must start and end with \"/\", and \"/\" itself cannot be a key."
  }
}

variable "tags" {
  description = "Tags for the resources, on top of the provider default tags."
  type        = map(string)
  default     = {}
}
