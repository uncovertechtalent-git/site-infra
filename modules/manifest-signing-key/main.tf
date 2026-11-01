# The key that signs a site's timetable manifest (chain-traveler: data/latest.json). An asymmetric ECDSA P-256 KMS key:
# the private half never leaves KMS, so no signing secret exists in GitHub or on a disk; the public half is read once
# (kms:GetPublicKey) and pinned in the app. Asymmetric keys cannot rotate automatically: a new key is added beside the old
# one and the app is told about both (README of the app, "Signed manifest").
#
# Who may sign is decided twice, like the state bucket: the IAM policy of the data role of the site (module
# github-deploy-role with sign_key_arn) allows kms:Sign on this one key, and the key policy below denies kms:Sign to every
# principal that is not that role, whatever an IAM policy in the account allows. The key policy has two statements:
#
#   - the account root may do everything with the key (kms:*). That is what lets IAM policies of the account grant access
#     to the key at all, and it keeps the key administrable by the account.
#   - kms:Sign is denied to every principal whose ARN is not the data role. For a role session, aws:PrincipalArn is the
#     ARN of the role, so the GitHub OIDC session of the data role matches.
#
# What this does not do: it does not deny kms:GetPublicKey or kms:Verify (the operator reads the public key by hand, and
# neither can produce a signature), and it does not stop an account administrator from changing the key policy
# (kms:PutKeyPolicy) and then signing. It narrows who can sign from day to day and makes a stray IAM grant useless; it is
# not a guard against a full administrator of the account.
#
# signer_role_arn is a string built from the account id and the role name, not a reference to the role: the role names
# this key in its own policy (sign_key_arn), and a reference the other way would be a cycle.

locals {
  # arn:<partition>:iam::<account>:role/<name>: the partition and the account of the role, for the root principal
  signer_parts = regex("^arn:([a-z-]+):iam::([0-9]{12}):role/", var.signer_role_arn)
  account_root = "arn:${local.signer_parts[0]}:iam::${local.signer_parts[1]}:root"

  key_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "AccountAdministersTheKey"
        Effect    = "Allow"
        Principal = { AWS = local.account_root }
        Action    = "kms:*"
        Resource  = "*"
      },
      {
        Sid       = "OnlyTheDataRoleSigns"
        Effect    = "Deny"
        Principal = "*"
        Action    = "kms:Sign"
        Resource  = "*"
        Condition = { ArnNotEquals = { "aws:PrincipalArn" = var.signer_role_arn } }
      },
    ]
  })
}

resource "aws_kms_key" "this" {
  description              = var.description
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = var.deletion_window_in_days
  policy                   = local.key_policy
  tags                     = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias_name}"
  target_key_id = aws_kms_key.this.key_id
}
