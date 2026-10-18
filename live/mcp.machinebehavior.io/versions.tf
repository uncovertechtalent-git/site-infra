terraform {
  required_version = "~> 1.16"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.68.0"
    }
    # Used by the mcp-endpoint module (the function zip); pinned here like aws.
    # tflint-ignore: terraform_unused_required_providers
    archive = {
      source  = "hashicorp/archive"
      version = "2.7.1"
    }
  }

  # Partial configuration: the bucket name comes from backend.hcl on the host
  # that runs plan and apply (terraform init -backend-config=backend.hcl).
  backend "s3" {
    key          = "site-infra/mcp.machinebehavior.io.tfstate"
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
      Stack      = "mcp.machinebehavior.io"
      ManagedBy  = "terraform"
      Repository = "uncovertechtalent-git/site-infra"
    }
  }
}
