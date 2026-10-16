# Cloudflare Access in front of the hostnames a Cloudflare tunnel publishes
# from the operator host. Without it, a service behind the tunnel is public
# the moment it starts. Operator-applied, like bootstrap: CI holds no
# Cloudflare token, so it validates and tests this stack but never plans it.
# Hostnames, account id and allowed emails are in local tfvars.

resource "cloudflare_zero_trust_organization" "this" {
  count = var.manage_organization ? 1 : 0

  account_id  = var.account_id
  name        = var.organization_name
  auth_domain = "${var.team_name}.cloudflareaccess.com"
}

module "tunnel_access" {
  source = "../../modules/cloudflare-access-app"

  account_id     = var.account_id
  name           = "Tunnel services"
  hostnames      = var.hostnames
  allowed_emails = var.allowed_emails

  depends_on = [cloudflare_zero_trust_organization.this]
}
