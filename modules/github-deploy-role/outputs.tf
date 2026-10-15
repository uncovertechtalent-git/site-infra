output "role_arn" {
  description = "ARN of the deploy role, for the workflow's AssumeRoleWithWebIdentity call."
  value       = aws_iam_role.this.arn
}

output "token_subject" {
  description = "The only OIDC token subject the role accepts."
  value       = local.subject
}
