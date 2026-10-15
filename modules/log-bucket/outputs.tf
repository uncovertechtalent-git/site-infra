output "bucket_name" {
  description = "Access log bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Access log bucket ARN."
  value       = aws_s3_bucket.this.arn
}

output "reader_role_arn" {
  description = "ARN of the read-only reader role, or null when no reader principals are set."
  value       = try(aws_iam_role.reader[0].arn, null)
}
