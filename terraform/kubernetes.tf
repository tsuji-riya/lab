resource "kubernetes_namespace_v1" "cloudflare" {
  metadata {
    name = "cloudflare"
  }
}

resource "kubernetes_secret_v1" "tunnel_token" {
  metadata {
    name      = "tunnel-token"
    namespace = kubernetes_namespace_v1.cloudflare.metadata[0].name
  }

  data = {
    token = module.cloudflare.tunnel_token
  }
}

resource "kubernetes_namespace_v1" "postgres" {
  metadata {
    name = "postgres"
  }
}

resource "kubernetes_namespace_v1" "claude" {
  metadata {
    name = "claude"
  }
}

# Pod が初回だけ `claude auth login` で使う。リフレッシュトークンは使い捨てなので、PVC が消えたときだけ入れ直す
resource "kubernetes_secret_v1" "claude_oauth" {
  metadata {
    name      = "claude-oauth"
    namespace = kubernetes_namespace_v1.claude.metadata[0].name
  }

  data = {
    refresh-token = var.claude_oauth_refresh_token
    scopes        = var.claude_oauth_scopes
  }
}
