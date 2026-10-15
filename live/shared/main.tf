# Shared by every site: the access log bucket. Its reader role and the GitHub
# OIDC provider live in the bootstrap stack, with all other IAM.

module "log_bucket" {
  source = "../../modules/log-bucket"

  bucket_name    = var.log_bucket_name
  retention_days = var.log_retention_days
}

# The reader role moved to the bootstrap stack (2026-10-15). Forget it here
# without destroying it; the bootstrap stack imported it.
removed {
  from = module.log_bucket.aws_iam_role.reader

  lifecycle {
    destroy = false
  }
}

removed {
  from = module.log_bucket.aws_iam_role_policy.reader

  lifecycle {
    destroy = false
  }
}
