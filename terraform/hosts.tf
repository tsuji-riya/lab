# hosts/ (ベアメタル層) が必要とする秘密と識別情報を、ここで生成して配る。
# 人の手を経由させないのが目的:
# - GitHub 側 (Environment hosts のシークレット / 変数) へは Terraform が直接書く
# - ノード側へは hosts/flash/fetch-tokens.sh が host_identity を取り出し、
#   flash.sh が焼き込み時に node.conf へ入れる
# 生成物は state (R2) に入る。state はすでにトンネル token を持つので境界は同じ。

locals {
  host_nodes = module.cloudflare.host_nodes
}

# ノードの SSH ホスト鍵。台が焼き直されても同じ鍵になるので、
# known_hosts を作り直す作業が永久に要らなくなる
resource "tls_private_key" "host_ssh" {
  for_each  = local.host_nodes
  algorithm = "ED25519"
}

# Host converge (CI) 専用のログイン鍵。本人の鍵とは別なので CI だけを失効できる
# (taint して apply → 次の converge が authorized_keys を更新する前に
#  新鍵が node.conf 経由でしか入らない点に注意: 既存台は runbook の手順で入れ替え)
resource "tls_private_key" "hosts_ci" {
  algorithm = "ED25519"
}

# k3s のクラスタ token。事前に決めておくことで、bootstrap 時に node1 から
# 取り出して配る段取りが不要になる (server_init も join もこの値を使う)
resource "random_password" "k3s_token" {
  length  = 48
  special = false
}

# 実行の承認は「main へのマージ」に一本化する。reviewer は置かず、
# main 以外 (PR ブランチ・fork) からはこの Environment の秘密に触れない
resource "github_repository_environment" "hosts" {
  repository  = "lab"
  environment = "hosts"

  deployment_branch_policy {
    protected_branches     = false
    custom_branch_policies = true
  }
}

resource "github_repository_environment_deployment_policy" "hosts_main" {
  repository     = "lab"
  environment    = github_repository_environment.hosts.environment
  branch_pattern = "main"
}

locals {
  hosts_env_secret_values = {
    HOSTS_SSH_KEY                 = tls_private_key.hosts_ci.private_key_openssh
    K3S_TOKEN                     = random_password.k3s_token.result
    HOSTS_CF_ACCESS_CLIENT_ID     = module.cloudflare.host_ops_service_token_client_id
    HOSTS_CF_ACCESS_CLIENT_SECRET = module.cloudflare.host_ops_service_token_client_secret
  }
  # for_each には秘密でないキーの集合だけを渡す (値は sensitive なので)
  hosts_env_secret_names = toset([
    "HOSTS_SSH_KEY",
    "K3S_TOKEN",
    "HOSTS_CF_ACCESS_CLIENT_ID",
    "HOSTS_CF_ACCESS_CLIENT_SECRET",
  ])
}

resource "github_actions_environment_secret" "hosts" {
  for_each        = local.hosts_env_secret_names
  repository      = "lab"
  environment     = github_repository_environment.hosts.environment
  secret_name     = each.key
  plaintext_value = local.hosts_env_secret_values[each.key]
}

# 公開鍵なので変数 (平文) でよい。トンネル経由のホスト名で引ける形
resource "github_actions_environment_variable" "hosts_known_hosts" {
  repository    = "lab"
  environment   = github_repository_environment.hosts.environment
  variable_name = "HOSTS_KNOWN_HOSTS"
  value = join("\n", [
    for n in sort(tolist(local.host_nodes)) :
    "${module.cloudflare.host_ssh_hostnames[n]} ${trimspace(tls_private_key.host_ssh[n].public_key_openssh)}"
  ])
}

# fetch-tokens.sh が読む。ノードごとの node.conf 追記分と公開ホスト鍵
output "host_identity" {
  sensitive = true
  value = {
    for n in local.host_nodes : n => {
      tunnel_token  = module.cloudflare.host_tunnel_tokens[n]
      host_key      = tls_private_key.host_ssh[n].private_key_openssh
      host_pubkey   = trimspace(tls_private_key.host_ssh[n].public_key_openssh)
      ci_ssh_pubkey = trimspace(tls_private_key.hosts_ci.public_key_openssh)
    }
  }
}

# LAN の Mac から ansible-playbook を流すとき用 (fetch-tokens.sh が取り出す)
output "k3s_token" {
  value     = random_password.k3s_token.result
  sensitive = true
}
