#!/bin/sh
# mini PC (node1-3) 用: 内蔵 SSD は取り出せないので、USB から起動して
# 内蔵ディスクへ image を流し込む。
#
# 流れ:
#   1. このスクリプトが USB メモリに node image を書く (flash.sh を流用)
#   2. ユーザーが node.conf を USB の FAT 領域にコピーし、mini PC を USB 起動
#      → 初回起動処理で IP が付き、Mac から SSH できる状態になる
#   3. このスクリプトが Mac 側で復号した image を SSH 越しに dd で内蔵へ流す
#      (age の秘密鍵は Mac から出ない。内蔵ディスクは起動元ではないので安全)
#   4. 内蔵側の EFI 領域に node.conf を書き、電源を切る
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
SSH="ssh -o StrictHostKeyChecking=accept-new riya@${IP}"

echo "== 手順1: USB メモリ ($USB) に image を書きます =="
./flash/flash.sh --node "$NODE" --image "$IMG" --device "$USB"
echo
echo "flash.sh の案内どおり、/tmp/node.conf を USB の FAT 領域へコピーしてください。"
printf 'コピーが終わったら Enter: '
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
# USB 起動側の EFI 領域 (/boot/efi) にある node.conf を、内蔵側 EFI へコピーする
$SSH "
  set -eu
  if [ -f /boot/efi/node.conf ]; then SRC=/boot/efi/node.conf;
  elif [ -f /boot/node.conf ]; then SRC=/boot/node.conf;
  else echo 'USB 側に node.conf が無い' >&2; exit 1; fi
  ESP=\$(sudo blkid -o device -t TYPE=vfat /dev/${TARGET}* | head -n 1)
  [ -n \"\$ESP\" ] || { echo '内蔵側の EFI 領域が見つからない' >&2; exit 1; }
  sudo mount \"\$ESP\" /mnt
  sudo cp \"\$SRC\" /mnt/node.conf
  ls -l /mnt/node.conf
  sudo umount /mnt
  sync
  echo 'node.conf 配置 OK'
"

echo "== 手順7: 電源を切ります =="
$SSH "sudo poweroff" || true
echo "USB メモリを抜いてから電源を入れてください。内蔵ディスクから初回起動します。"
echo "起動後は ssh riya@${IP} で確認し、ansible-playbook site.yml --limit ${NODE} を実行。"
