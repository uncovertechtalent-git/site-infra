terraform {
  required_version = "~> 1.16"

  required_providers {
    cloudflare = {
      source  = "cloudflare/cloudflare"
      version = "5.26.0"
    }
  }

  # Same private state bucket as the AWS stacks (backend.hcl on the operator host).
  backend "s3" {
    key          = "site-infra/cloudflare-access.tfstate"
    region       = "eu-central-1"
    encrypt      = true
    use_lockfile = true
  }
}

# The API token comes from CLOUDFLARE_API_TOKEN in the environment of the one
# terraform process that needs it, on the operator host. It is never in a file
# of this repository or in CI.
provider "cloudflare" {}
