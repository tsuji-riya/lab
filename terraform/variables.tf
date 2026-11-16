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

variable "claude_oauth_refresh_token" {
  type      = string
  sensitive = true
}

variable "claude_oauth_scopes" {
  type = string
}
