# ask mbio: the public, read-only MCP server of machinebehavior.io
# (functions/ask_mbio/handler.py, README "ask mbio").
#
# Launch: attach_dns = false keeps mcp.machinebehavior.io off DNS; the server
# answers on its CloudFront domain only (output endpoint), for the preview.
# Set it to true only after the site's privacy notice covers the server
# (uncovertechtalent/machinebehavior.io#11) and on Stefan Coetzee's go.

locals {
  host          = "mcp.machinebehavior.io"
  function_name = "ask-mbio"
}

data "aws_s3_bucket" "logs" {
  bucket = var.log_bucket_name
}

module "endpoint" {
  source = "../../modules/mcp-endpoint"

  name               = local.function_name
  host               = local.host
  zone_id            = var.zone_id
  attach_dns         = var.attach_dns
  handler_file       = "${path.root}/../../functions/ask_mbio/handler.py"
  package_dir        = "${path.root}/.build"
  execution_role_arn = "arn:aws:iam::${var.aws_account_id}:role/${local.function_name}-lambda"
  origin_secret      = var.origin_secret

  origin_secret_previous = var.origin_secret_previous
  log_bucket_arn         = data.aws_s3_bucket.logs.arn

  environment = {
    ASK_SITE        = "https://machinebehavior.io"
    ASK_TTL_SECONDS = "900"
  }
}
