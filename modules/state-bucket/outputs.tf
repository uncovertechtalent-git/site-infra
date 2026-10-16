output "bucket_name" {
  description = "State bucket name, for the backend setting of the other stacks."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "State bucket ARN."
  value       = aws_s3_bucket.this.arn
}
