# The key that signs a site's timetable manifest (chain-traveler: data/latest.json). An asymmetric ECDSA P-256 KMS key:
# the private half never leaves KMS, so no signing secret exists in GitHub or on a disk; the public half is read once
# (kms:GetPublicKey) and pinned in the app. Only the principals that an IAM policy names may use it (the data role of the
# site, module github-deploy-role with sign_key_arn); the key policy is the account default, so IAM decides.
# Asymmetric keys cannot rotate automatically: a new key is added beside the old one and the app is told about both
# (README of the app, "Signed manifest").

resource "aws_kms_key" "this" {
  description              = var.description
  key_usage                = "SIGN_VERIFY"
  customer_master_key_spec = "ECC_NIST_P256"
  deletion_window_in_days  = var.deletion_window_in_days
  tags                     = var.tags
}

resource "aws_kms_alias" "this" {
  name          = "alias/${var.alias_name}"
  target_key_id = aws_kms_key.this.key_id
}
