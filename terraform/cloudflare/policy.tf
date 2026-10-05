resource "cloudflare_zero_trust_access_policy" "owner_only" {
  account_id       = var.account_id
  name             = "owner-only"
  decision         = "allow"
  session_duration = "24h"

  include = [
    {
      email = {
        email = "tsuji.riya@gmail.com"
      }
    },
  ]
}
