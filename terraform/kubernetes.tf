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

resource "kubernetes_namespace_v1" "gitea" {
  metadata {
    name = "gitea"
  }
}

resource "random_password" "gitea_db" {
  length  = 32
  special = false
}

# CNPG の managed role 用(postgres namespace)
resource "kubernetes_secret_v1" "gitea_db_role" {
  metadata {
    name      = "gitea-db"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
    labels = {
      "cnpg.io/reload" = "true"
    }
  }

  type = "kubernetes.io/basic-auth"

  data = {
    username = "gitea"
    password = random_password.gitea_db.result
  }
}

# Gitea の接続用(gitea namespace)。Secret は namespace をまたげないので同じ値を別に置く
resource "kubernetes_secret_v1" "gitea_db" {
  metadata {
    name      = "gitea-db"
    namespace = kubernetes_namespace_v1.gitea.metadata[0].name
  }

  data = {
    password = random_password.gitea_db.result
  }
}

resource "random_password" "gitea_admin" {
  length  = 32
  special = false
}

resource "kubernetes_secret_v1" "gitea_admin" {
  metadata {
    name      = "gitea-admin"
    namespace = kubernetes_namespace_v1.gitea.metadata[0].name
  }

  data = {
    username = "riya"
    password = random_password.gitea_admin.result
  }
}

resource "kubernetes_secret_v1" "gitea_oauth_github" {
  metadata {
    name      = "gitea-oauth-github"
    namespace = kubernetes_namespace_v1.gitea.metadata[0].name
  }

  data = {
    key    = var.github_oauth_client_id
    secret = var.github_oauth_client_secret
  }
}
