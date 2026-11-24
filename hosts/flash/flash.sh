#!/bin/sh
# 使い方: ./flash/flash.sh --node node7 --image alpine-...-aarch64.img --device /dev/disk6
# image を丸ごと書き、boot パーティションに node.conf を注入する。
# macOS / Linux 両対応 (書き込みは dd、注入は FAT マウント前提)。
set -eu
NODE="" IMG="" DEV=""
while [ $# -gt 0 ]; do
  case "$1" in
    --node) NODE="$2"; shift 2;;
    --image) IMG="$2"; shift 2;;
    --device) DEV="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
if [ -z "$NODE" ] || [ -z "$IMG" ] || [ -z "$DEV" ]; then
  echo "必須: --node --image --device" >&2; exit 1
fi

ROW=$(grep "^${NODE}|" "$(dirname "$0")/nodes.conf") || { echo "nodes.conf に無い: $NODE" >&2; exit 1; }
IP=$(echo "$ROW" | cut -d'|' -f2); ROLE=$(echo "$ROW" | cut -d'|' -f3)

echo "== $NODE ($IP, $ROLE) へ $IMG を $DEV に書きます =="
echo "対象ディスクを間違えると全データが消えます。5秒後に確認プロンプトを出します。"
sleep 5
printf '本当に書き込みますか? [yes/NO] '
read -r ans; [ "$ans" = "yes" ] || { echo "中止"; exit 1; }

AGE_KEY="${AGE_KEY:-$HOME/.config/lab-hosts-age.txt}"
case "$IMG" in
  *.img.zst.age)
    command -v age >/dev/null 2>&1 || { echo "age が必要です: brew install age" >&2; exit 1; }
    [ -f "$AGE_KEY" ] || { echo "age 秘密鍵が無い: $AGE_KEY" >&2; exit 1; }
    age -d -i "$AGE_KEY" "$IMG" | zstd -dc | sudo dd of="$DEV" bs=4m status=progress;;
  *.img.zst)
    zstd -dc "$IMG" | sudo dd of="$DEV" bs=4m status=progress;;
  *)
    sudo dd if="$IMG" of="$DEV" bs=4m status=progress;;
esac
sync

PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/lab_admin.pub}"
[ -f "$PUBKEY_FILE" ] || { echo "公開鍵が無い: $PUBKEY_FILE (ssh-keygen で ~/.ssh/lab_admin を作る)" >&2; exit 1; }
PUBKEY=$(cat "$PUBKEY_FILE")
# Tailscale の auth key は任意。Mac にファイルがあれば一緒に埋め込む
TS_LINE=""
TS_KEY_FILE="${TS_KEY_FILE:-$HOME/.config/lab-hosts-ts-authkey}"
if [ -f "$TS_KEY_FILE" ]; then
  TS_LINE="TS_AUTHKEY='$(cat "$TS_KEY_FILE")'"
else
  echo "注意: $TS_KEY_FILE が無いので Tailscale 参加はスキップされます"
fi
cat > /tmp/node.conf <<EOF
NODE_HOSTNAME=${NODE}.k3s.riya.work
NODE_IP=${IP}
NODE_GATEWAY=192.168.1.1
NODE_ROLE=${ROLE}
SSH_PUBKEY='${PUBKEY}'
${TS_LINE}
EOF
echo "node.conf を boot パーティションへ手動コピーしてください (FAT なので Finder/エクスプローラ可):"
echo "  cp /tmp/node.conf <BOOTボリューム>/node.conf"
echo "完了したら対象マシンを起動し、ssh riya@${IP} で疎通確認。"
