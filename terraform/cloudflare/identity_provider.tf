# Access のログインを GitHub にする。誰を通すかは policy.tf のメールで決める
resource "cloudflare_zero_trust_access_identity_provider" "github" {
  account_id = var.account_id
  name       = "GitHub"
  type       = "github"

  config = {
    client_id     = var.github_client_id
    client_secret = var.github_client_secret
  }
}
