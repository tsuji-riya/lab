resource "cloudflare_zero_trust_access_application" "longhorn" {
  account_id       = var.account_id
  name             = "Longhorn"
  domain           = local.longhorn_hostname
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.owner_only.id
      precedence = 1
    },
  ]
}

resource "cloudflare_zero_trust_access_application" "headlamp" {
  account_id       = var.account_id
  name             = "Headlamp"
  domain           = local.headlamp_hostname
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.owner_only.id
      precedence = 1
    },
  ]
}
