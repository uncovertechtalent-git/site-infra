output "site_bucket_name" {
  description = "Target bucket of the app deploys (secret SITE_BUCKET of the app repository)."
  value       = module.site.bucket_name
}

output "distribution_id" {
  description = "Distribution to invalidate after a deploy (secret CLOUDFRONT_DISTRIBUTION_ID); also the distribution_id of this site in the bootstrap tfvars."
  value       = module.site.distribution_id
}

output "distribution_domain_name" {
  description = "CloudFront domain name: where the app answers while domain_ready is false."
  value       = module.site.distribution_domain_name
}

output "distribution_hosts" {
  description = "Hosts attached to the distribution (empty while domain_ready is false)."
  value       = module.site.distribution_hosts
}

output "log_prefix" {
  description = "Prefix of this site's access logs in the log bucket."
  value       = module.site.log_prefix
}
