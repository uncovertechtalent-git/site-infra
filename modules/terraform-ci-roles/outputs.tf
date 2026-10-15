output "plan_role_arn" {
  description = "Role for plans on pull requests (repository secret AWS_PLAN_ROLE_ARN)."
  value       = aws_iam_role.plan.arn
}

output "apply_role_arn" {
  description = "Role for applies in the protected environment (environment secret AWS_APPLY_ROLE_ARN)."
  value       = aws_iam_role.apply.arn
}
