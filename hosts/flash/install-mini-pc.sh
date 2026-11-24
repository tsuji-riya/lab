#!/bin/sh
# mini PC (node1-3) 用: 内蔵 SSD は取り出せないので、USB から起動して
# 内蔵ディスクへ image を流し込む。
#
# 流れ:
#   1. このスクリプトが USB メモリに node image を書く (flash.sh を流用)
#   2. (macOS なら node.conf は flash.sh が自動注入) mini PC を USB 起動
#      → 初回起動処理で IP が付き、Mac から SSH できる状態になる
#   3. このスクリプトが Mac 側で復号した image を SSH 越しに dd で内蔵へ流す
#      (age の秘密鍵は Mac から出ない。内蔵ディスクは起動元ではないので安全)
#   4. 内蔵側の EFI 領域に node.conf を書き、電源を切る
#      (USB 側の node.conf は初回起動処理が消すので、Mac から改めて流す)
#   5. ユーザーが USB を抜いて電源 ON → 内蔵から初回起動
#
# 使い方:
#   ./hosts/flash/install-mini-pc.sh --node node1 \
#     --image alpine-3.24.4-x86_64.img.zst.age --usb-device /dev/disk6
set -eu
cd "$(dirname "$0")/.."

NODE="" IMG="" USB=""
while [ $# -gt 0 ]; do
  case "$1" in
    --node) NODE="$2"; shift 2;;
    --image) IMG="$2"; shift 2;;
    --usb-device) USB="$2"; shift 2;;
    *) echo "unknown arg: $1" >&2; exit 1;;
  esac
done
if [ -z "$NODE" ] || [ -z "$IMG" ] || [ -z "$USB" ]; then
  echo "必須: --node --image --usb-device" >&2; exit 1
fi

ROW=$(grep "^${NODE}|" flash/nodes.conf) || { echo "nodes.conf に無い: $NODE" >&2; exit 1; }
IP=$(echo "$ROW" | cut -d'|' -f2)
# USB 起動中の OS と、内蔵から起動した後の OS はホスト鍵が別物になる。
# known_hosts を汚さないよう、USB 起動中の接続は専用の known_hosts に閉じる
KH=$(mktemp "${TMPDIR:-/tmp}/known_hosts.XXXXXX")
trap 'rm -f "$KH"' EXIT
SSH="ssh -o StrictHostKeyChecking=accept-new -o UserKnownHostsFile=$KH riya@${IP}"

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

echo "== 手順3: SSH 疎通を待ちます ($IP) =="
until $SSH true 2>/dev/null; do
  printf '.'
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

echo "== 手順5: 復号しながら SSH 越しに書き込みます =="
AGE_KEY="${AGE_KEY:-$HOME/.config/lab-hosts-age.txt}"
case "$IMG" in
  *.age) age -d -i "$AGE_KEY" "$IMG" | zstd -dc ;;
  *.zst) zstd -dc "$IMG" ;;
  *) cat "$IMG" ;;
esac | $SSH "sudo dd of=/dev/${TARGET} bs=4M status=progress conv=fsync"

echo "== 手順6: 内蔵側 EFI 領域に node.conf を書きます =="
# dd 直後はカーネルが古いパーティション表を見ているので、先に読み直させる。
# node.conf は Mac で生成し直して標準入力で流す (token を一時ファイルに置かない)
./flash/flash.sh --node "$NODE" --emit-conf | $SSH "
  set -eu
  sudo partx -d /dev/${TARGET} 2>/dev/null || true
  sudo partx -a /dev/${TARGET}
  sudo mdev -s
  ESP=\$(sudo blkid -o device -t TYPE=vfat /dev/${TARGET}* | head -n 1)
  [ -n \"\$ESP\" ] || { echo '内蔵側の EFI 領域が見つからない' >&2; exit 1; }
  sudo mount \"\$ESP\" /mnt
  sudo tee /mnt/node.conf >/dev/null
  ls -l /mnt/node.conf
  sudo umount /mnt
  sync
  echo 'node.conf 配置 OK'
"

echo "== 手順7: 電源を切ります =="
$SSH "sudo poweroff" || true
echo "USB メモリを抜いてから電源を入れてください。内蔵ディスクから初回起動します。"
# 内蔵から起動した OS はホスト鍵が新しくなるので、Mac 側の古い記録を消しておく
ssh-keygen -R "$IP" >/dev/null 2>&1 || true
echo "起動後は ssh riya@${IP} で確認し、ansible-playbook site.yml --limit ${NODE} を実行。"
