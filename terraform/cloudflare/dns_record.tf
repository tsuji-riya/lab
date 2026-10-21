resource "cloudflare_dns_record" "longhorn" {
  zone_id = var.zone_id
  name    = local.longhorn_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "headlamp" {
  zone_id = var.zone_id
  name    = local.headlamp_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "logs" {
  zone_id = var.zone_id
  name    = local.logs_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# 誰でも見られる公開サイトなので Access アプリは作らない
resource "cloudflare_dns_record" "anubis" {
  zone_id = var.zone_id
  name    = local.anubis_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}
