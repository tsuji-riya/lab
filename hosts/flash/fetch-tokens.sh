#!/bin/sh
# Terraform が作ったホスト用トンネルトークンを Mac に取り込む。
# 前提: terraform/ の state にアクセスできること (backend の認証情報と
# CLOUDFLARE_API_TOKEN が環境にあること)。
#
# 使い方:
#   sh hosts/flash/fetch-tokens.sh              # トークンを ~/.config/lab-hosts-cf/ に書く
#   sh hosts/flash/fetch-tokens.sh --gh-secrets # ついでに Actions 用シークレットも更新
set -eu
cd "$(dirname "$0")/../.."

OUT_DIR="${CF_TOKEN_DIR:-$HOME/.config/lab-hosts-cf}"
export OUT_DIR
install -d -m 700 "$OUT_DIR"

terraform -chdir=terraform output -json host_tunnel_tokens \
  | python3 -c '
import json, os, sys
tokens = json.load(sys.stdin)
out = os.environ["OUT_DIR"]
for node, token in tokens.items():
    path = os.path.join(out, f"{node}.token")
    with open(path, "w") as f:
        f.write(token)
    os.chmod(path, 0o600)
    print(f"wrote {path}")
'

if [ "${1:-}" = "--gh-secrets" ]; then
  gh secret set CF_ACCESS_CLIENT_ID --body \
    "$(terraform -chdir=terraform output -raw host_ops_service_token_client_id)"
  gh secret set CF_ACCESS_CLIENT_SECRET --body \
    "$(terraform -chdir=terraform output -raw host_ops_service_token_client_secret)"
  echo "GitHub シークレット CF_ACCESS_CLIENT_ID/SECRET を更新しました"
fi
