output "application_id" {
  description = "Access application id."
  value       = cloudflare_zero_trust_access_application.this.id
}

output "policy_id" {
  description = "Allow policy id."
  value       = cloudflare_zero_trust_access_policy.allow.id
}

output "identity_provider_ids" {
  description = "Login methods the application allows."
  value       = local.identity_provider_ids
}
