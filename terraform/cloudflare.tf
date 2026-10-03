module "cloudflare" {
  source = "./cloudflare"

  account_id = local.cloudflare_account_id
  zone_id    = local.cloudflare_zone_id
}
