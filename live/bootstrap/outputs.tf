output "state_bucket_name" {
  description = "State bucket name, for backend.hcl."
  value       = module.state_bucket.bucket_name
}
