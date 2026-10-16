output "role_arn" {
  description = "ARN of the reader role, for the role_arn of the stats job's AWS profile."
  value       = aws_iam_role.this.arn
}
