#!/bin/sh
# 使い方: ./flash/flash.sh --node node7 --image alpine-...-aarch64.img --device /dev/disk6
# image を丸ごと書き、boot パーティションに node.conf を注入する。
# macOS / Linux 両対応 (書き込みは dd、注入は FAT マウント前提)。
set -eu
NODE="" IMG="" DEV="" INJECT_ONLY=""
while [ $# -gt 0 ]; do
  case "$1" in
    --node) NODE="$2"; shift 2;;
    --image) IMG="$2"; shift 2;;
    --device) DEV="$2"; shift 2;;
    --inject-only) INJECT_ONLY=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
if [ -z "$NODE" ] || [ -z "$DEV" ] || { [ -z "$IMG" ] && [ -z "$INJECT_ONLY" ]; }; then
  echo "必須: --node --device と (--image または --inject-only)" >&2; exit 1
fi

ROW=$(grep "^${NODE}|" "$(dirname "$0")/nodes.conf") || { echo "nodes.conf に無い: $NODE" >&2; exit 1; }
IP=$(echo "$ROW" | cut -d'|' -f2); ROLE=$(echo "$ROW" | cut -d'|' -f3)

if [ -z "$INJECT_ONLY" ]; then
echo "== $NODE ($IP, $ROLE) へ $IMG を $DEV に書きます =="
echo "対象ディスクを間違えると全データが消えます。5秒後に確認プロンプトを出します。"
sleep 5
printf '本当に書き込みますか? [yes/NO] '
read -r ans; [ "$ans" = "yes" ] || { echo "中止"; exit 1; }

# macOS は挿したディスクを自動マウントするため、先に unmountDisk しないと
# dd が Resource busy で落ちる。書き込みは raw デバイス (/dev/rdiskN) が速い
WRITE_DEV="$DEV"
if [ "$(uname)" = "Darwin" ]; then
  diskutil unmountDisk "$DEV" || true
  WRITE_DEV="/dev/r$(basename "$DEV")"
fi

AGE_KEY="${AGE_KEY:-$HOME/.config/lab-hosts-age.txt}"
case "$IMG" in
  *.img.zst.age)
    command -v age >/dev/null 2>&1 || { echo "age が必要です: brew install age" >&2; exit 1; }
    [ -f "$AGE_KEY" ] || { echo "age 秘密鍵が無い: $AGE_KEY" >&2; exit 1; }
    age -d -i "$AGE_KEY" "$IMG" | zstd -dc | sudo dd of="$WRITE_DEV" bs=4m status=progress;;
  *.img.zst)
    zstd -dc "$IMG" | sudo dd of="$WRITE_DEV" bs=4m status=progress;;
  *)
    sudo dd if="$IMG" of="$WRITE_DEV" bs=4m status=progress;;
esac
sync
fi

PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/lab_admin.pub}"
[ -f "$PUBKEY_FILE" ] || { echo "公開鍵が無い: $PUBKEY_FILE (ssh-keygen で ~/.ssh/lab_admin を作る)" >&2; exit 1; }
PUBKEY=$(cat "$PUBKEY_FILE")
# Cloudflare Tunnel のトークンはノード別。Mac にファイルがあれば埋め込む
CF_LINE=""
CF_TOKEN_FILE="${CF_TOKEN_DIR:-$HOME/.config/lab-hosts-cf}/${NODE}.token"
if [ -f "$CF_TOKEN_FILE" ]; then
  CF_LINE="CF_TUNNEL_TOKEN='$(cat "$CF_TOKEN_FILE")'"
else
  echo "注意: $CF_TOKEN_FILE が無いので Cloudflare Tunnel は無効になります"
fi
cat > /tmp/node.conf <<EOF
NODE_HOSTNAME=${NODE}.k3s.riya.work
NODE_IP=${IP}
NODE_GATEWAY=192.168.1.1
NODE_ROLE=${ROLE}
SSH_PUBKEY='${PUBKEY}'
${CF_LINE}
EOF
# macOS では boot パーティションをマウントして自動で流し込む
INJECTED=""
if [ "$(uname)" = "Darwin" ]; then
  diskutil mount "${DEV}s1" >/dev/null 2>&1 || true
  MP=$(diskutil info "${DEV}s1" 2>/dev/null | sed -n 's/^[[:space:]]*Mount Point:[[:space:]]*//p')
  if [ -n "$MP" ] && [ -d "$MP" ]; then
    cp /tmp/node.conf "$MP/node.conf"
    echo "node.conf を $MP に書き込みました"
    INJECTED=1
    diskutil eject "$DEV" >/dev/null 2>&1 || true
  fi
fi
if [ -z "$INJECTED" ]; then
  echo "node.conf を boot パーティションへ手動コピーしてください (FAT なので Finder/エクスプローラ可):"
  echo "  cp /tmp/node.conf <BOOTボリューム>/node.conf"
fi
echo "完了したら対象マシンを起動し、ssh riya@${IP} で疎通確認。"
