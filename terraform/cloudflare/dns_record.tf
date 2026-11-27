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

# ROM は配信せず利用者が手元から読み込むので、Access なしで公開する
resource "cloudflare_dns_record" "fantasy" {
  zone_id = var.zone_id
  name    = local.fantasy_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# 公開 API (statuses の 1 パスだけ)。Access なしで、CORS は status_cors で付ける
resource "cloudflare_dns_record" "status_api" {
  zone_id = var.zone_id
  name    = local.status_api_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# status.riya.work は GitHub Pages。証明書の発行に GitHub へ直接届く必要があるので proxied = false
resource "cloudflare_dns_record" "status" {
  zone_id = var.zone_id
  name    = local.status_hostname
  type    = "CNAME"
  content = "tsuji-riya.github.io"
  proxied = false
  ttl     = 1
}
