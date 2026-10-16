# tflint: every Terraform language rule plus the AWS ruleset (invalid
# arguments, regions, deprecated attributes and the like). The plugin is
# pinned; tflint --init verifies its signature.
config {
  call_module_type = "local"
}

plugin "terraform" {
  enabled = true
  preset  = "all"
}

plugin "aws" {
  enabled = true
  version = "0.49.0"
  source  = "github.com/terraform-linters/tflint-ruleset-aws"
}
