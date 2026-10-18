output "function_name" {
  description = "Lambda function name."
  value       = aws_lambda_function.this.function_name
}

output "distribution_domain_name" {
  description = "CloudFront domain name (dxxxx.cloudfront.net): the preview endpoint before attach_dns."
  value       = aws_cloudfront_distribution.this.domain_name
}

output "endpoint" {
  description = "MCP endpoint URL (the host once attach_dns is true, else the distribution domain)."
  value       = "https://${var.attach_dns ? var.host : aws_cloudfront_distribution.this.domain_name}/mcp"
}

output "log_prefix" {
  description = "Key prefix of the endpoint's access logs in the log bucket."
  value       = local.log_prefix
}
