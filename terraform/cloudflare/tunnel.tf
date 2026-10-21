locals {
  longhorn_hostname = "longhorn.riya.work"
  headlamp_hostname = "headlamp.riya.work"
  logs_hostname     = "logs.riya.work"
  anubis_hostname   = "anubis.riya.work"
}

resource "random_bytes" "tunnel_secret" {
  length = 32
}

resource "cloudflare_zero_trust_tunnel_cloudflared" "k3s" {
  account_id    = var.account_id
  name          = "k3s"
  tunnel_secret = random_bytes.tunnel_secret.base64
}

resource "cloudflare_zero_trust_tunnel_cloudflared_config" "k3s" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s.id

  config = {
    ingress = [
      {
        hostname = local.longhorn_hostname
        service  = "http://longhorn-frontend.longhorn-system.svc.cluster.local:80"
      },
      {
        hostname = local.headlamp_hostname
        service  = "http://headlamp.headlamp.svc.cluster.local:80"
      },
      {
        hostname = local.logs_hostname
        service  = "http://victoria-logs-victoria-logs-single-server.victoria-logs.svc.cluster.local:9428"
      },
      {
        hostname = local.anubis_hostname
        service  = "http://anubis.anubis.svc.cluster.local:80"
      },
      {
        service = "http_status:404"
      },
    ]
  }
}

data "cloudflare_zero_trust_tunnel_cloudflared_token" "k3s" {
  account_id = var.account_id
  tunnel_id  = cloudflare_zero_trust_tunnel_cloudflared.k3s.id
}
