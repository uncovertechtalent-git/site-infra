output "site_bucket_name" {
  description = "Target bucket of the content deploy."
  value       = module.site.bucket_name
}

output "distribution_id" {
  description = "Distribution to invalidate after a deploy."
  value       = module.site.distribution_id
}

output "distribution_domain_name" {
  description = "CloudFront domain name."
  value       = module.site.distribution_domain_name
}

output "distribution_hosts" {
  description = "Hosts attached to the distribution."
  value       = module.site.distribution_hosts
}

output "dns_target" {
  description = "Where the apex and www records point."
  value       = module.site.dns_target
}

output "log_prefix" {
  description = "Prefix of this site's access logs in the log bucket."
  value       = module.site.log_prefix
}
