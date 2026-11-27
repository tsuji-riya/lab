#!/usr/bin/env bash
# k3s API を Cloudflare Access の TCP トンネルで 127.0.0.1:6443 に引き込む。
# 前提: cloudflared が入っていて、TUNNEL_SERVICE_TOKEN_ID / _SECRET が渡っていること。
# 経路 k3s-api.riya.work は Terraform 管理 (server 3台がコネクタ)。
#
# 疎通は「ポートが開いたか」ではなく実際の HTTPS 応答で判定する。cloudflared は
# ローカルの待受をすぐ開くので、Access に拒否されていてもポート確認は通ってしまう
# (2026-11-24 に deploy がこれで原因不明の connection reset になった)。
set -euo pipefail

# トークンが空だと cloudflared はブラウザログイン待ちで黙って止まる
# (Dependabot の PR には Actions のシークレットが渡らない)
: "${TUNNEL_SERVICE_TOKEN_ID:?サービストークンが渡っていない}"
: "${TUNNEL_SERVICE_TOKEN_SECRET:?サービストークンが渡っていない}"

host=k3s-api.riya.work
log="/tmp/cloudflared-${host}.log"
nohup cloudflared access tcp --hostname "$host" --url 127.0.0.1:6443 \
  > "$log" 2>&1 &
for _ in $(seq 1 15); do
  # 認証なしの /version は 401/403 でも返ってくれば経路は生きている
  code=$(curl -sk -o /dev/null -w '%{http_code}' --max-time 5 \
    https://127.0.0.1:6443/version || true)
  if [ -n "$code" ] && [ "$code" != "000" ]; then
    echo "k3s API reachable via ${host} (HTTP ${code})"
    exit 0
  fi
  sleep 2
done

cat "$log"
echo "::error::${host} で k3s API に届かない (Access のトークン / コネクタ / クラスタを確認)"
exit 1
