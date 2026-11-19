resource "kubernetes_namespace_v1" "cloudflare" {
  metadata {
    name = "cloudflare"
    labels = {
      # cloudflared は非特権で動くので Pod Security Standards の restricted を強制する
      "pod-security.kubernetes.io/enforce" = "restricted"
      "pod-security.kubernetes.io/audit"   = "restricted"
      "pod-security.kubernetes.io/warn"    = "restricted"
    }
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
    labels = {
      # CNPG の Pod は非特権で動くので baseline を強制する
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}
