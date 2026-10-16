output "application_id" {
  description = "Access application id."
  value       = module.tunnel_access.application_id
}

output "auth_domain" {
  description = "Login domain, when this stack manages the organization."
  value       = try(cloudflare_zero_trust_organization.this[0].auth_domain, null)
}
