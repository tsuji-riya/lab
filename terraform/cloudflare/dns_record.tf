resource "cloudflare_dns_record" "longhorn" {
  zone_id = var.zone_id
  name    = local.longhorn_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "gitea" {
  zone_id = var.zone_id
  name    = local.gitea_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

resource "cloudflare_dns_record" "gitea_ssh" {
  zone_id = var.zone_id
  name    = local.gitea_ssh_hostname
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
