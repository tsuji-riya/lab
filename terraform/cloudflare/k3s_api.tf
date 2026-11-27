# CI (deploy / Host OS update) が k3s API に届くための経路。
# 1本のトンネルを server 3台 (node1-3) が同時にコネクタとして張るので、
# どの1台が落ちても経路は残る (同一トンネルへの複数コネクタは cloudflared の標準機能)。
# クラスタ内ではなくホストで張るのは、全台作り直し直後 (クラスタがまだ空で
# クラスタ内の cloudflared が居ない) でも deploy が API に届くようにするため。
locals {
  k3s_api_hostname = "k3s-api.riya.work"
}

resource "random_bytes" "k3s_api_tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "k3s_api" {
  account_id    = var.account_id
  name          = "k3s-api"
  tunnel_secret = random_bytes.k3s_api_tunnel_secret.base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "k3s_api" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s_api.id

  config = {
    ingress = [
      {
        hostname = local.k3s_api_hostname
        service  = "tcp://localhost:6443"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "k3s_api" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s_api.id
}

resource "cloudflare_dns_record" "k3s_api" {
  zone_id = var.zone_id
  name    = local.k3s_api_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s_api.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# CI はホスト SSH と同じサービストークン、本人はメールで通す
resource "cloudflare_zero_trust_access_application" "k3s_api" {
  account_id       = var.account_id
  name             = "k3s API"
  domain           = local.k3s_api_hostname
  type             = "self_hosted"
  session_duration = "24h"

  policies = [
    {
      id         = cloudflare_zero_trust_access_policy.host_ops_service_token.id
      precedence = 1
    },
    {
      id         = cloudflare_zero_trust_access_policy.owner_only.id
      precedence = 2
    },
  ]
}

output "k3s_api_tunnel_token" {
  value     = data.cloudflare_zero_trust_tunnel_cloudflared_token.k3s_api.token
  sensitive = true
}
