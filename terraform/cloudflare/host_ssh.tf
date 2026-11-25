# ホスト SSH 用 Cloudflare Tunnel (PR #42/#43 のホスト層)。
# ノードごとにトンネルを張り、ssh-nodeN.riya.work -> ssh://localhost:22
# を Access で保護する。GitHub Actions (Host converge) はサービストークンで、
# 本人は owner_only ポリシー (メール) でブラウザ SSH できる。
locals {
  host_nodes = toset([
    "node1", "node2", "node3", "node4", "node5", "node6", "node7",
  ])
  host_ssh_hostname = { for n in local.host_nodes : n => "ssh-${n}.riya.work" }
}

resource "random_bytes" "host_tunnel_secret" {
  for_each = local.host_nodes
  length   = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "host" {
  for_each      = local.host_nodes
  account_id    = var.account_id
  name          = "host-${each.key}"
  tunnel_secret = random_bytes.host_tunnel_secret[each.key].base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "host" {
  for_each   = local.host_nodes
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.host[each.key].id

  config = {
    ingress = [
      {
        hostname = local.host_ssh_hostname[each.key]
        service  = "ssh://localhost:22"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "host" {
  for_each   = local.host_nodes
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.host[each.key].id
}

resource "cloudflare_dns_record" "host_ssh" {
  for_each = local.host_nodes
  zone_id  = var.zone_id
  name     = local.host_ssh_hostname[each.key]
  type     = "CNAME"
  content  = "${cloudflare_zero_trust_tunnel_cloudflared.host[each.key].id}.cfargotunnel.com"
  proxied  = true
  ttl      = 1
}

# GitHub Actions 専用のサービストークン
resource "cloudflare_zero_trust_access_service_token" "host_ops" {
  account_id = var.account_id
  name       = "host-ops-ci"
}

resource "cloudflare_zero_trust_access_policy" "host_ops_service_token" {
  account_id = var.account_id
  name       = "host-ops-service-token"
  decision   = "non_identity"

  include = [
    {
      service_token = {
        token_id = cloudflare_zero_trust_access_service_token.host_ops.id
      }
    },
  ]
}

resource "cloudflare_zero_trust_access_application" "host_ssh" {
  for_each         = local.host_nodes
  account_id       = var.account_id
  name             = "Host SSH ${each.key}"
  domain           = local.host_ssh_hostname[each.key]
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

output "host_nodes" {
  value = local.host_nodes
}

output "host_ssh_hostnames" {
  value = local.host_ssh_hostname
}

output "host_tunnel_tokens" {
  value     = { for n in local.host_nodes : n => data.cloudflare_zero_trust_tunnel_cloudflared_token.host[n].token }
  sensitive = true
}

output "host_ops_service_token_client_id" {
  value     = cloudflare_zero_trust_access_service_token.host_ops.client_id
  sensitive = true
}

output "host_ops_service_token_client_secret" {
  value     = cloudflare_zero_trust_access_service_token.host_ops.client_secret
  sensitive = true
}
