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

# ROM は配信せず利用者が手元から読み込むので、Access なしで公開する
resource "cloudflare_dns_record" "fantasy" {
  zone_id = var.zone_id
  name    = local.fantasy_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# status.riya.work (GitHub Pages) が読む Gatus の API。公開の死活情報だけなので Access なし
resource "cloudflare_dns_record" "status_api" {
  zone_id = var.zone_id
  name    = local.status_api_hostname
  type    = "CNAME"
  content = "${cloudflare_zero_trust_tunnel_cloudflared.k3s.id}.cfargotunnel.com"
  proxied = true
  ttl     = 1
}

# ページ本体は tsuji-riya/status.riya.work の GitHub Pages。証明書を GitHub に発行させるためプロキシしない
resource "cloudflare_dns_record" "status" {
  zone_id = var.zone_id
  name    = local.status_hostname
  type    = "CNAME"
  content = "tsuji-riya.github.io"
  proxied = false
  ttl     = 1
}
