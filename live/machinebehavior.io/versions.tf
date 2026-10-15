terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.67.0"
    }
  }

  # Partial configuration: the bucket name comes from backend.hcl on the host
  # that runs plan and apply (terraform init -backend-config=backend.hcl).
  backend "s3" {
    key          = "site-infra/machinebehavior.io.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

provider "aws" {
  region              = var.region
  allowed_account_ids = [var.aws_account_id]

  default_tags {
    tags = {
      Project    = "site-infra"
      Stack      = "machinebehavior.io"
      ManagedBy  = "terraform"
      Repository = "uncovertechtalent-git/site-infra"
    }
  }
}
