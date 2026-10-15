output "log_bucket_name" {
  description = "Access log bucket name, input of each site stack."
  value       = module.log_bucket.bucket_name
}
