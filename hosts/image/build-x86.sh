#!/bin/sh
# x86_64 (node1-3) 用 raw UEFI image を生成する。
# 公式 alpine-make-vm-image を版と sha1 で固定して使う。VM 向けツールなので
# 実機向けに3点を上書きする:
# - カーネル: 既定の linux-virt は実機ドライバが乏しいので lts を指定
# - initramfs: 既定機能 (kms scsi virtio) に、内蔵 NVMe/SATA と USB 起動用を足す
# - ブートローダ: ツールは EFI シェル用 startup.nsh しか置かないため、
#   configure-chroot.sh が systemd-boot を EFI/BOOT/BOOTX64.EFI に置く
set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.24.4}"
BRANCH="v$(echo "$ALPINE_VERSION" | cut -d. -f1,2)"
TOOL_VERSION="0.13.3"
TOOL_SHA1="f17ef4997496ace524a8e8e578d944f3552255bb"
OUT="out/alpine-${ALPINE_VERSION}-x86_64.img"
cd "$(dirname "$0")/.."
mkdir -p out .cache

grep -h -v '^#' image/packages.common image/packages.x86_64 | grep -v '^$' > .cache/packages.txt

# alpine-make-vm-image は qemu-nbd を使うため、ホスト (runner) の
# カーネルに nbd モジュールが必要。コンテナ内からは /lib/modules が
# 見えず modprobe できないので、ホスト側で先にロードしておく
sudo modprobe nbd max_part=16

# image は中身 (約 580MiB, 2026-11) が収まる最小に近い 1G にして、USB と内蔵への
# 書き込み量を減らす。rootfs は node-firstboot の growpart でディスク全体に広がる。
# 中身が増えて溢れるとビルド中の apk が失敗するので、そのときは増やす
# ビルドは Alpine コンテナ内で行う (apk の root 構築が最も素直なため)
docker run --rm --privileged -v "$PWD:/work" -v /lib/modules:/lib/modules:ro -w /work alpine:3.24 sh -eu -c "
  # qemu-nbd のバイナリは qemu-img パッケージに同梱されている (3.24)
  apk add --no-cache qemu-img e2fsprogs sfdisk rsync curl
  cd .cache
  [ -f alpine-make-vm-image ] || {
    curl -fsSLO https://raw.githubusercontent.com/alpinelinux/alpine-make-vm-image/v${TOOL_VERSION}/alpine-make-vm-image
    echo '${TOOL_SHA1}  alpine-make-vm-image' | sha1sum -c
    chmod +x alpine-make-vm-image
  }
  cd /work
  ./.cache/alpine-make-vm-image \
    --arch x86_64 \
    --branch ${BRANCH} \
    --image-format raw \
    --image-size 1G \
    --boot-mode UEFI \
    --kernel-flavor lts \
    --initfs-features \"kms scsi virtio ata nvme usb\" \
    --packages \"\$(cat .cache/packages.txt)\" \
    --repositories-file image/repositories \
    --fs-skel-dir image/overlay \
    --fs-skel-chown root:root \
    --script-chroot ${OUT} -- image/configure-chroot.sh
"

# image には設計上シークレットが入らない (識別情報と鍵は焼き込み時に node.conf
# で入る) ので暗号化しない。完全性は sha256 と build provenance で担保する
zstd -19 -T0 "$OUT" -o "$OUT.zst" && rm "$OUT"
(cd out && sha256sum "$(basename "$OUT.zst")" > "$(basename "$OUT.zst").sha256")
ls -lh out/
echo "OK: $OUT.zst"
