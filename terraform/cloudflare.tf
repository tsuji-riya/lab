module "cloudflare" {
  source = "./cloudflare"

  account_id = local.cloudflare_account_id
  zone_id    = local.cloudflare_zone_id

  github_client_id     = var.access_github_client_id
  github_client_secret = var.access_github_client_secret
}
