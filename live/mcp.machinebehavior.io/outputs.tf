output "endpoint" {
  description = "MCP endpoint URL: the CloudFront domain until attach_dns, then https://mcp.machinebehavior.io/mcp."
  value       = module.endpoint.endpoint
}

output "function_name" {
  description = "Lambda function name, for its log group."
  value       = module.endpoint.function_name
}

output "attach_dns" {
  description = "Whether mcp.machinebehavior.io is on DNS."
  value       = var.attach_dns
}
