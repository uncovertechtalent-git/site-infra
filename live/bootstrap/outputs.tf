output "state_bucket_name" {
  description = "State bucket name: backend.hcl, and the repository secret TF_STATE_BUCKET."
  value       = module.state_bucket.bucket_name
}

output "plan_role_arn" {
  description = "Repository secret AWS_PLAN_ROLE_ARN of the infrastructure repository."
  value       = module.terraform_ci_roles.plan_role_arn
}

output "apply_role_arn" {
  description = "Secret AWS_APPLY_ROLE_ARN of its production environment."
  value       = module.terraform_ci_roles.apply_role_arn
}

output "deploy_role_arns" {
  description = "Per site: repository secret AWS_DEPLOY_ROLE_ARN of the site repository."
  value       = { for site, m in module.deploy_role : site => m.role_arn }
}

output "log_reader_role_arn" {
  description = "role_arn of the stats job's AWS profile."
  value       = module.log_reader.role_arn
}

output "manifest_signing_key_arns" {
  description = "Per site that signs its manifest: repository secret SIGNING_KEY_ARN of the site repository. The public key is read with aws kms get-public-key and pinned in the app (app/keys.js)."
  value       = { for site, m in module.manifest_key : site => m.key_arn }
}

output "data_role_arns" {
  description = "Per site with a data prefix: repository secret AWS_DATA_ROLE_ARN of the site repository."
  value       = { for site, m in module.data_role : site => m.role_arn }
}
