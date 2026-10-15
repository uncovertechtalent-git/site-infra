output "bucket_name" {
  description = "Access log bucket name."
  value       = aws_s3_bucket.this.id
}

output "bucket_arn" {
  description = "Access log bucket ARN."
  value       = aws_s3_bucket.this.arn
}
