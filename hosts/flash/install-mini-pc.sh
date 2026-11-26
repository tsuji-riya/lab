#!/bin/sh
# mini PC (node1-3) 用: 内蔵 SSD は取り出せないので、USB から起動して
# 内蔵ディスクへ image を流し込む。
#
# 流れ:
#   1. このスクリプトが USB メモリに node image を書く (flash.sh を流用)
#   2. (macOS なら node.conf は flash.sh が自動注入) mini PC を USB 起動
#      → 初回起動処理で IP が付き、Mac から SSH できる状態になる
#   3. このスクリプトが image を SSH 越しに dd で内蔵へ流す
#      (内蔵ディスクは起動元ではないので実行中でも安全に書ける)
#   4. 内蔵側の EFI 領域に node.conf を書き、電源を切る
#      (USB 側の node.conf は初回起動処理が消すので、Mac から改めて流す)
#   5. ユーザーが USB を抜いて電源 ON → 内蔵から初回起動
#
# 使い方:
#   ./hosts/flash/install-mini-pc.sh --node node1 \
#     --image alpine-3.24.4-x86_64.img.zst --usb-device /dev/disk6
#
# 途中で止まったとき、USB 起動まで済んでいれば手順3 (SSH 疎通) から再開できる:
#   ./hosts/flash/install-mini-pc.sh --node node1 \
#     --image alpine-3.24.4-x86_64.img.zst --resume-from-ssh
set -eu
cd "$(dirname "$0")/.."

NODE="" IMG="" USB="" RESUME=""
while [ $# -gt 0 ]; do
  case "$1" in
    --node) NODE="$2"; shift 2;;
    --image) IMG="$2"; shift 2;;
    --usb-device) USB="$2"; shift 2;;
    --resume-from-ssh) RESUME=1; shift;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
if [ -z "$NODE" ] || [ -z "$IMG" ] || { [ -z "$USB" ] && [ -z "$RESUME" ]; }; then
  echo "必須: --node --image と (--usb-device または --resume-from-ssh)" >&2; exit 1
fi

ROW=$(grep "^${NODE}|" flash/nodes.conf) || { echo "nodes.conf に無い: $NODE" >&2; exit 1; }
IP=$(echo "$ROW" | cut -d'|' -f2)
# ホスト鍵は Terraform 生成の固定値なので、USB 起動中も内蔵から起動した後も
# 同じ鍵になる。fetch-tokens.sh が書いた known_hosts で厳密に検証する
# 鍵は node.conf で配った本人用 (flash.sh の PUBKEY_FILE と対)。指定しないと ssh は
# ~/.ssh/id_* しか試さず Permission denied になる
ADMIN_KEY="${ADMIN_KEY:-$HOME/.ssh/lab_admin}"
[ -f "$ADMIN_KEY" ] || { echo "秘密鍵が無い: $ADMIN_KEY (ADMIN_KEY で指定可)" >&2; exit 1; }
SSH="ssh -i $ADMIN_KEY -o IdentitiesOnly=yes -o BatchMode=yes -o ConnectTimeout=5 -o StrictHostKeyChecking=yes -o UserKnownHostsFile=$HOME/.config/lab-hosts/known_hosts riya@${IP}"

if [ -z "$RESUME" ]; then
echo "== 手順1: USB メモリ ($USB) に image を書きます =="
./flash/flash.sh --node "$NODE" --image "$IMG" --device "$USB"
echo
echo "macOS では node.conf は自動注入済み。flash.sh が手動コピーを案内した場合だけ、"
echo "その案内どおり USB の FAT 領域へコピーしてください。"
printf '準備ができたら Enter: '
read -r _

echo "== 手順2: mini PC を USB から起動してください =="
echo "BIOS で USB を起動順の先頭にするか、ブートメニューを開いて USB を選ぶ。"
printf '起動して 1 分ほど待ったら Enter: '
read -r _
fi

echo "== 手順3: SSH 疎通を待ちます ($IP) =="
# 起動待ちの間は失敗が普通なので黙って待つが、1分ごとに直近の理由を出す
# (鍵の不一致やホスト鍵の不一致は待っても直らないので、気づけるようにする)
n=0
until err=$($SSH true 2>&1); do
  n=$((n + 1))
  printf '.'
  [ $((n % 12)) -eq 0 ] && printf '\n  まだ繋がらない: %s\n' "$(printf '%s' "$err" | tail -n 1)"
  sleep 5
done
echo " 疎通 OK"

echo "== 手順4: 内蔵ディスクの確認 =="
$SSH lsblk -d -o NAME,SIZE,MODEL,TRAN
echo "起動元 (USB) は TRAN=usb のもの。書き込み先は内蔵 (nvme / sata) の方。"
printf '書き込み先のデバイス名を入力 (例: nvme0n1 または sda): '
read -r TARGET
[ -n "$TARGET" ] || { echo "中止" >&2; exit 1; }
printf "本当に /dev/%s の全データを消して image を書きますか? [yes/NO] " "$TARGET"
read -r ans; [ "$ans" = "yes" ] || { echo "中止"; exit 1; }

echo "== 手順5: SSH 越しに書き込みます =="
case "$IMG" in
  *.zst) zstd -dc "$IMG" ;;
  *) cat "$IMG" ;;
esac | $SSH "sudo dd of=/dev/${TARGET} bs=4M status=progress conv=fsync"

echo "== 手順6: 内蔵側 EFI 領域に node.conf を書きます =="
# dd 直後はカーネルが古いパーティション表を見ており、読み直し (partx) をしても
# /dev/sda1 が作られないことがあった (node1、2026-11-26、原因未特定)。デバイスファイルに
# 頼らず、ディスク上のパーティション表から partition 1 (ESP) の位置を読んで loop で開く。
# node.conf は Mac で生成し直して標準入力で流す (token を一時ファイルに置かない)
./flash/flash.sh --node "$NODE" --emit-conf | $SSH "
  set -eu
  l=\$(sudo sfdisk -d /dev/${TARGET} 2>/dev/null | grep -E '^/dev/${TARGET}p?1 ')
  s=\$(echo \"\$l\" | sed 's/.*start= *\([0-9]*\).*/\1/')
  n=\$(echo \"\$l\" | sed 's/.*size= *\([0-9]*\).*/\1/')
  [ -n \"\$s\" ] && [ -n \"\$n\" ] || { echo '内蔵側のパーティション表に partition 1 が無い' >&2; exit 1; }
  sudo mount -o loop,offset=\$((s * 512)),sizelimit=\$((n * 512)) /dev/${TARGET} /mnt
  sudo tee /mnt/node.conf >/dev/null
  ls -l /mnt/node.conf
  sudo umount /mnt
  sync
  echo 'node.conf 配置 OK'
"

echo "== 手順7: 電源を切ります =="
$SSH "sudo poweroff" || true
echo "USB メモリを抜いてから電源を入れてください。内蔵ディスクから初回起動します。"
echo "k3s の導入と join は Host converge が行う (急ぐなら Actions から手動実行)。"
