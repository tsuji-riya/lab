#!/bin/sh
# Terraform が生成した台ごとの識別情報を Mac に取り出す (焼き込みの前に1回)。
# GitHub 側 (Environment hosts のシークレット / 変数) へは Terraform が直接
# 書くので、ここで扱うのは焼き込みに要るものだけ。
#
# 前提: deploy ワークフローと同じ認証情報が環境にあること。
#   AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY  (R2 = state の置き場)
#   R2_BUCKET / R2_ENDPOINT                    (backend の init 用)
#
# 出力 (~/.config/lab-hosts/、本人だけが読める):
#   nodeN.env    flash.sh が node.conf に追記する秘密 (トンネル token、
#                SSH ホスト鍵、CI 用公開鍵、server は k3s API のトンネル token)
#   known_hosts  LAN の IP で引けるホスト公開鍵 (inventory/hosts.yml と
#                install-mini-pc.sh が検証に使う。焼き直しても不変)
#   k3s.env      LAN から ansible-playbook を流すときの K3S_TOKEN
#
# 使い方: sh hosts/flash/fetch-tokens.sh
set -eu
cd "$(dirname "$0")/../.."

# deploy ワークフローと同じ形で毎回 init する (冪等で数秒)。.terraform の有無で
# 省略すると、古い .terraform (backend 未設定や provider 不足) を初期化済みと誤認する
: "${R2_BUCKET:?R2_BUCKET が必要です}" "${R2_ENDPOINT:?R2_ENDPOINT が必要です}"
terraform -chdir=terraform init -input=false -reconfigure \
  -backend-config="bucket=${R2_BUCKET}" \
  -backend-config="endpoints={s3=\"${R2_ENDPOINT}\"}" >/dev/null

OUT_DIR="${HOSTS_SECRETS_DIR:-$HOME/.config/lab-hosts}"
export OUT_DIR
(umask 077 && mkdir -p "$OUT_DIR")
chmod 700 "$OUT_DIR"

# パイプに直結すると terraform の失敗が JSON の解析エラーに化けるので、先に受ける
IDENTITY=$(terraform -chdir=terraform output -json host_identity)
printf '%s' "$IDENTITY" | python3 -c '
import base64, json, os, sys
ids = json.load(sys.stdin)
out = os.environ["OUT_DIR"]
ips = {}
with open("hosts/flash/nodes.conf") as f:
    for line in f:
        if line.startswith("#") or not line.strip():
            continue
        node, ip = line.split("|")[:2]
        ips[node] = ip

def write(name, text):
    path = os.path.join(out, name)
    fd = os.open(path, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w") as f:
        f.write(text)
    os.chmod(path, 0o600)
    print(f"wrote {path}")

known = []
for node, v in sorted(ids.items()):
    host_key = base64.b64encode(v["host_key"].encode()).decode()
    tt, ci, pub = v["tunnel_token"], v["ci_ssh_pubkey"], v["host_pubkey"]
    api = v["api_tunnel_token"]
    # repr は値を単引用符で囲む (値に引用符は含まれない) ので sh で source できる
    env = (f"CF_TUNNEL_TOKEN={tt!r}\n"
           f"SSH_HOST_KEY_B64={host_key!r}\n"
           f"SSH_PUBKEY_CI={ci!r}\n")
    if api:  # k3s API のトンネルは server だけ
        env += f"CF_API_TUNNEL_TOKEN={api!r}\n"
    write(f"{node}.env", env)
    known.append(f"{ips[node]} {pub}")
write("known_hosts", "\n".join(known) + "\n")
'

printf "%s='%s'\n" K3S_TOKEN \
  "$(terraform -chdir=terraform output -raw k3s_token)" \
  | (umask 077 && cat > "$OUT_DIR/k3s.env")
echo "wrote $OUT_DIR/k3s.env (LAN から流すときは: set -a; . $OUT_DIR/k3s.env; set +a)"
