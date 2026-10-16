output "bucket_name" {
  description = "Site bucket name, the target of the content deploy."
  value       = aws_s3_bucket.site.id
}

output "bucket_arn" {
  description = "Site bucket ARN."
  value       = aws_s3_bucket.site.arn
}

output "distribution_id" {
  description = "CloudFront distribution id, for invalidations."
  value       = aws_cloudfront_distribution.this.id
}

output "distribution_arn" {
  description = "CloudFront distribution ARN."
  value       = aws_cloudfront_distribution.this.arn
}

output "distribution_domain_name" {
  description = "CloudFront domain name (dxxxx.cloudfront.net)."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "distribution_hosts" {
  description = "Host names attached to the distribution."
  value       = local.distribution_hosts
}

output "dns_target" {
  description = "Where the apex records point (www follows the apex)."
  value       = var.dns_target
}

output "log_prefix" {
  description = "Key prefix of this site's access logs in the log bucket."
  value       = local.log_prefix
}
