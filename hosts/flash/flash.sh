#!/bin/sh
# 使い方:
#   ./flash/flash.sh --node node7 --image alpine-...-aarch64.img.zst --device /dev/disk6
#   ./flash/flash.sh --node node7 --device /dev/disk6 --inject-only  # node.conf だけ書く
#   ./flash/flash.sh --node node1 --emit-conf                        # node.conf を標準出力へ
# image を丸ごと書き、boot パーティションに node.conf を注入する。
# macOS / Linux 両対応 (書き込みは dd、注入は FAT マウント前提)。
# 前提: sh hosts/flash/fetch-tokens.sh で台ごとの秘密を取り出してあること。
set -eu
NODE="" IMG="" DEV="" INJECT_ONLY="" EMIT_CONF=""
while [ $# -gt 0 ]; do
  case "$1" in
    --node) NODE="$2"; shift 2;;
    --image) IMG="$2"; shift 2;;
    --device) DEV="$2"; shift 2;;
    --inject-only) INJECT_ONLY=1; shift;;
    --emit-conf) EMIT_CONF=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
[ -n "$NODE" ] || { echo "必須: --node" >&2; exit 1; }
if [ -z "$EMIT_CONF" ]; then
  if [ -z "$DEV" ] || { [ -z "$IMG" ] && [ -z "$INJECT_ONLY" ]; }; then
    echo "必須: --node --device と (--image または --inject-only)" >&2; exit 1
  fi
fi

ROW=$(grep "^${NODE}|" "$(dirname "$0")/nodes.conf") || { echo "nodes.conf に無い: $NODE" >&2; exit 1; }
IP=$(echo "$ROW" | cut -d'|' -f2); ROLE=$(echo "$ROW" | cut -d'|' -f3); ARCH=$(echo "$ROW" | cut -d'|' -f4)

# node.conf の中身を標準出力に書く (トンネル token とホスト鍵を含むので扱いに注意)
emit_conf() {
  PUBKEY_FILE="${PUBKEY_FILE:-$HOME/.ssh/lab_admin.pub}"
  [ -f "$PUBKEY_FILE" ] || { echo "公開鍵が無い: $PUBKEY_FILE (ssh-keygen で ~/.ssh/lab_admin を作る)" >&2; exit 1; }
  # 台ごとの秘密 (トンネル token・SSH ホスト鍵・CI 用公開鍵) は Terraform が
  # 生成し、fetch-tokens.sh が書き出したものをそのまま追記する
  SECRETS_FILE="${HOSTS_SECRETS_DIR:-$HOME/.config/lab-hosts}/${NODE}.env"
  [ -f "$SECRETS_FILE" ] || { echo "$SECRETS_FILE が無い。先に sh hosts/flash/fetch-tokens.sh を実行する" >&2; exit 1; }
  printf '%s\n' \
    "NODE_HOSTNAME=${NODE}.k3s.riya.work" \
    "NODE_IP=${IP}" \
    "NODE_GATEWAY=192.168.1.1" \
    "NODE_ROLE=${ROLE}" \
    "SSH_PUBKEY='$(cat "$PUBKEY_FILE")'"
  cat "$SECRETS_FILE"
}

if [ -n "$EMIT_CONF" ]; then
  emit_conf
  exit 0
fi

if [ -z "$INJECT_ONLY" ]; then
# 取り違え防止: image 名の arch と nodes.conf の arch が一致すること
case "$(basename "$IMG")" in
  *"-${ARCH}.img"*) ;;
  *) echo "$NODE は $ARCH だが image が違う: $IMG" >&2; exit 1;;
esac
# 配布物の sha256 が隣にあれば検証する (Release から一緒に落とした場合)
if [ -f "$IMG.sha256" ]; then
  (cd "$(dirname "$IMG")" && shasum -a 256 -c "$(basename "$IMG").sha256")
fi
echo "== $NODE ($IP, $ROLE, $ARCH) へ $IMG を $DEV に書きます =="
echo "対象ディスクを間違えると全データが消えます。5秒後に確認プロンプトを出します。"
sleep 5
printf '本当に書き込みますか? [yes/NO] '
read -r ans; [ "$ans" = "yes" ] || { echo "中止"; exit 1; }

# macOS は挿したディスクを自動マウントするため、先に unmountDisk しないと
# dd が Resource busy で落ちる。書き込みは raw デバイス (/dev/rdiskN) が速い。
# bs の単位は BSD dd が小文字 (4m)、GNU dd が大文字 (4M)
WRITE_DEV="$DEV" BS=4M
if [ "$(uname)" = "Darwin" ]; then
  diskutil unmountDisk "$DEV" || true
  WRITE_DEV="/dev/r$(basename "$DEV")" BS=4m
fi

case "$IMG" in
  *.img.zst)
    zstd -dc "$IMG" | sudo dd of="$WRITE_DEV" bs="$BS" status=progress;;
  *)
    sudo dd if="$IMG" of="$WRITE_DEV" bs="$BS" status=progress;;
esac
sync
fi

# node.conf は秘密を含むので、本人だけが読める一時ファイルに置き、
# 自動注入できたら消す
CONF_FILE=$(umask 077 && mktemp "${TMPDIR:-/tmp}/node.conf.XXXXXX")
emit_conf > "$CONF_FILE"

# macOS では boot パーティションをマウントして自動で流し込む
INJECTED=""
if [ "$(uname)" = "Darwin" ]; then
  diskutil mount "${DEV}s1" >/dev/null 2>&1 || true
  MP=$(diskutil info "${DEV}s1" 2>/dev/null | sed -n 's/^[[:space:]]*Mount Point:[[:space:]]*//p')
  if [ -n "$MP" ] && [ -d "$MP" ]; then
    cp "$CONF_FILE" "$MP/node.conf"
    echo "node.conf を $MP に書き込みました"
    INJECTED=1
    diskutil eject "$DEV" >/dev/null 2>&1 || true
  fi
fi
if [ -n "$INJECTED" ]; then
  rm -f "$CONF_FILE"
else
  echo "node.conf を boot パーティションへ手動コピーしてください (FAT なので Finder/エクスプローラ可):"
  echo "  cp $CONF_FILE <BOOTボリューム>/node.conf && rm $CONF_FILE"
  echo "($CONF_FILE は秘密を含みます。コピー後に必ず消すこと)"
fi
echo "完了したら対象マシンを起動する。k3s の導入と join は Host converge"
echo "(main へのマージ / 6時間ごと / 手動実行) が行う。急ぐなら Actions から手動実行。"
