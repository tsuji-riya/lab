provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  host                   = "https://127.0.0.1:6443"
  cluster_ca_certificate = var.k8s_cluster_ca_certificate
  client_certificate     = var.k8s_client_certificate
  client_key             = var.k8s_client_key
}
