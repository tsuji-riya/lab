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

resource "kubernetes_namespace_v1" "gitea" {
  metadata {
    name = "gitea"
    labels = {
      # チャートの init コンテナが root 権限を要らないので baseline で足りる
      "pod-security.kubernetes.io/enforce" = "baseline"
      "pod-security.kubernetes.io/audit"   = "baseline"
      "pod-security.kubernetes.io/warn"    = "baseline"
    }
  }
}

# app.ini に入るので、INI でコメント扱いされる記号を避けて英数字だけにする
resource "random_password" "gitea_db" {
  length  = 32
  special = false
}

resource "random_password" "gitea_admin" {
  length  = 32
  special = false
}

# CNPG の managed role (infrastructure/postgres/cluster.yaml) が読む
resource "kubernetes_secret_v1" "gitea_db_role" {
  metadata {
    name      = "gitea-db"
    namespace = kubernetes_namespace_v1.postgres.metadata[0].name
    labels = {
      # パスワードを変えたら CNPG にロールを更新させる
      "cnpg.io/reload" = "true"
    }
  }

  type = "kubernetes.io/basic-auth"
  data = {
    username = "gitea"
    password = random_password.gitea_db.result
  }
}

# Gitea チャートの additionalConfigSources。キーが app.ini のセクション名になる
resource "kubernetes_secret_v1" "gitea_db" {
  metadata {
    name      = "gitea-db"
    namespace = kubernetes_namespace_v1.gitea.metadata[0].name
  }

  data = {
    database = "PASSWD=${random_password.gitea_db.result}"
  }
}

# 初回に作る管理者。パスワードは kubectl -n gitea get secret gitea-admin で取り出す
resource "kubernetes_secret_v1" "gitea_admin" {
  metadata {
    name      = "gitea-admin"
    namespace = kubernetes_namespace_v1.gitea.metadata[0].name
  }

  data = {
    username = "tsuji-riya"
    password = random_password.gitea_admin.result
  }
}

resource "kubernetes_secret_v1" "gitea_oauth_github" {
  metadata {
    name      = "gitea-oauth-github"
    namespace = kubernetes_namespace_v1.gitea.metadata[0].name
  }

  data = {
    key    = var.gitea_github_client_id
    secret = var.gitea_github_client_secret
  }
}
