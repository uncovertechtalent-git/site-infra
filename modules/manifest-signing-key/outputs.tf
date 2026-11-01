output "key_arn" {
  description = "ARN of the key: repository secret SIGNING_KEY_ARN of the site repository, and sign_key_arn of the data role."
  value       = aws_kms_key.this.arn
}

output "alias_name" {
  description = "The alias, for reading the public key by name (aws kms get-public-key --key-id alias/...)."
  value       = aws_kms_alias.this.name
}
