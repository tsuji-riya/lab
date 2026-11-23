variable "cloudflare_api_token" {
  type      = string
  sensitive = true
}

variable "k8s_cluster_ca_certificate" {
  type      = string
  sensitive = true
}

variable "k8s_client_certificate" {
  type      = string
  sensitive = true
}

variable "k8s_client_key" {
  type      = string
  sensitive = true
}

# GitHub OAuth App (Gitea 用、callback: https://gitea.riya.work/user/oauth2/github/callback)
variable "gitea_github_client_id" {
  type = string
}

variable "gitea_github_client_secret" {
  type      = string
  sensitive = true
}
