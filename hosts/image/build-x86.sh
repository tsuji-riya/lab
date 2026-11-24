#!/bin/sh
# x86_64 (node1-3) 用 raw UEFI image を生成する。
# 公式 alpine-make-vm-image を版と sha1 で固定して使う (VM 用途だが UEFI/EFI-stub の
# raw image はベアメタル mini PC でもそのまま起動する)。
set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.24.4}"
BRANCH="v$(echo "$ALPINE_VERSION" | cut -d. -f1,2)"
TOOL_VERSION="0.13.3"
TOOL_SHA1="f17ef4997496ace524a8e8e578d944f3552255bb"
OUT="out/alpine-${ALPINE_VERSION}-x86_64.img"
cd "$(dirname "$0")/.."
mkdir -p out .cache

grep -v '^#' image/packages.common image/packages.x86_64 | grep -v '^$' > .cache/packages.txt

# alpine-make-vm-image は qemu-nbd を使うため、ホスト (runner) の
# カーネルに nbd モジュールが必要。コンテナ内からは /lib/modules が
# 見えず modprobe できないので、ホスト側で先にロードしておく
sudo modprobe nbd max_part=16

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
    --image-size 4G \
    --boot-mode UEFI \
    --packages \"\$(cat .cache/packages.txt)\" \
    --repositories-file image/repositories \
    --fs-skel-dir image/overlay \
    --script-chroot ${OUT} -- image/configure-chroot.sh
"

# 圧縮して age 暗号化し、平文は残さない。sha256 は暗号化後の配布物に対して作る
zstd -19 -T0 "$OUT" -o "$OUT.zst" && rm "$OUT"
./image/encrypt-image.sh "$OUT.zst"
ls -lh out/
echo "OK: $OUT.zst.age"
