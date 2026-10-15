output "log_bucket_name" {
  description = "Access log bucket name, input of each site stack."
  value       = module.log_bucket.bucket_name
}

output "log_reader_role_arn" {
  description = "Role the stats job assumes to read the access logs."
  value       = module.log_bucket.reader_role_arn
}

output "github_oidc_provider_arn" {
  description = "IAM OIDC provider for GitHub Actions, or null while disabled."
  value       = try(aws_iam_openid_connect_provider.github[0].arn, null)
}
