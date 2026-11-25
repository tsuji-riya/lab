provider "cloudflare" {
  api_token = var.cloudflare_api_token
}

provider "kubernetes" {
  host                   = "https://127.0.0.1:6443"
  cluster_ca_certificate = var.k8s_cluster_ca_certificate
  client_certificate     = var.k8s_client_certificate
  client_key             = var.k8s_client_key
}

# hosts/ 用の Environment・シークレット・変数を Terraform から直接書く。
# GITHUB_TOKEN ではシークレットを書けないため、この repo だけに絞った
# fine-grained PAT (Administration / Secrets / Variables: write) を使う
provider "github" {
  owner = "tsuji-riya"
  token = var.github_token
}
