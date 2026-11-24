#!/bin/sh
# aarch64 (node4-7, Raspberry Pi) 用 image を組み立てる。
#
# なぜ自前組み立てか: 公式 alpine-rpi tarball は FAT 上で動く diskless 配布で、
# x86 側 (ext4 の sys モード) と運用形態が揃わない。そこで apk-tools-static で
# ext4 root を sys モード構築し、boot パーティション (FAT) には
# raspberrypi-bootloader と linux-rpi の kernel/initramfs を配置する。
# world と overlay は x86 と完全共通。arm ネイティブランナー前提 (binfmt 不要)。
#
# 注意: 初回は node7 の実機で起動確認するまで「未検証の前提」を含む。
# 詰まるのは大抵 cmdline.txt の root= と initramfs の USB 対応なので、
# 失敗したらシリアルコンソールのログをこの repo の issue に残すこと。
set -eu

ALPINE_VERSION="${ALPINE_VERSION:-3.24.4}"
BRANCH="v$(echo "$ALPINE_VERSION" | cut -d. -f1,2)"
MIRROR="https://dl-cdn.alpinelinux.org/alpine/${BRANCH}"
IMG="out/alpine-${ALPINE_VERSION}-aarch64.img"
cd "$(dirname "$0")/.."
mkdir -p out .cache mnt-boot mnt-root

sudo apt-get update -qq && sudo apt-get install -y -qq zstd dosfstools e2fsprogs curl

# apk-tools-static (aarch64) を版で固定して取得
APK_STATIC_VER=$(curl -fsSL "$MIRROR/main/aarch64/APKINDEX.tar.gz" | tar -xzO APKINDEX 2>/dev/null \
  | awk '/^P:apk-tools-static$/{f=1} f&&/^V:/{print substr($0, 3); exit}')
[ -n "$APK_STATIC_VER" ] || { echo "apk-tools-static の版が引けない" >&2; exit 1; }
if [ ! -x .cache/apk.static ]; then
  curl -fsSL "$MIRROR/main/aarch64/apk-tools-static-${APK_STATIC_VER}.apk" -o .cache/apk-tools-static.apk
  tar -xzf .cache/apk-tools-static.apk -C .cache sbin/apk.static
  mv .cache/sbin/apk.static .cache/apk.static
fi

# 署名鍵が無いと APKINDEX が UNTRUSTED になって全パッケージが引けない。
# alpine-keys から鍵だけを取り出して --keys-dir で渡す
KEYS_VER=$(curl -fsSL "$MIRROR/main/aarch64/APKINDEX.tar.gz" | tar -xzO APKINDEX 2>/dev/null \
  | awk '/^P:alpine-keys$/{f=1} f&&/^V:/{print substr($0, 3); exit}')
[ -n "$KEYS_VER" ] || { echo "alpine-keys の版が引けない" >&2; exit 1; }
if [ ! -d .cache/keys ]; then
  mkdir -p .cache/keys
  curl -fsSL "$MIRROR/main/aarch64/alpine-keys-${KEYS_VER}.apk" -o .cache/alpine-keys.apk
  tar -xzf .cache/alpine-keys.apk -C .cache/keys etc/apk/keys 2>/dev/null
fi
KEYS_DIR="$PWD/.cache/keys/etc/apk/keys"

# 4G image: boot(FAT32 256M) + root(ext4)
dd if=/dev/zero of="$IMG" bs=1M count=4096 status=none
sfdisk "$IMG" <<'EOF'
label: dos
unit: sectors
start=2048, size=524288, type=c, bootable
start=526336, type=83
EOF
LOOP=$(sudo losetup -fP --show "$IMG")
cleanup() { sudo umount mnt-boot mnt-root 2>/dev/null || true; sudo losetup -d "$LOOP" 2>/dev/null || true; }
trap cleanup EXIT
sudo mkfs.vfat -F 32 -n LABBOOT "${LOOP}p1" >/dev/null
sudo mkfs.ext4 -q -L root "${LOOP}p2"
sudo mount "${LOOP}p1" mnt-boot
sudo mount "${LOOP}p2" mnt-root

# rootfs を sys モードで構築 (world は x86 と共通 + rpi 追加分)
grep -h -v '^#' image/packages.common image/packages.aarch64 | grep -v '^$' > .cache/packages.txt
# パッケージ一覧は1行1パッケージ。位置パラメータへ読み込んでから渡す
set --
while IFS= read -r pkg; do
  [ -n "$pkg" ] && set -- "$@" "$pkg"
done < .cache/packages.txt
sudo .cache/apk.static \
  --repository "$MIRROR/main" --repository "$MIRROR/community" \
  --keys-dir "$KEYS_DIR" \
  --root "$PWD/mnt-root" --initdb add --no-cache "$@"

# 共通 overlay を重ね、chroot で仕上げ (鍵・サービス有効化・manifest)
sudo cp -a --no-preserve=ownership image/overlay/. mnt-root/
for d in dev proc sys; do sudo mount --bind "/$d" "mnt-root/$d"; done
# chroot 内のダウンロード用にランナーの resolv.conf を一時的に使う
sudo cp /etc/resolv.conf mnt-root/etc/resolv.conf
sudo cp image/configure-chroot.sh mnt-root/tmp/configure-chroot.sh
sudo chroot mnt-root /bin/sh /tmp/configure-chroot.sh
for d in dev proc sys; do sudo umount "mnt-root/$d"; done

# ランナーの resolv.conf (Azure の stub resolver) を image に残すと
# ノードの DNS が死ぬ。lab の DNS に差し替える (firstboot も毎回書く)
echo "nameserver 192.168.1.1" | sudo tee mnt-root/etc/resolv.conf >/dev/null

# fstab: boot は FAT、root は ext4 (USB SSD 前提でデバイス名は UUID でなく LABEL)
sudo mkdir -p mnt-root/boot
cat <<'EOF' | sudo tee mnt-root/etc/fstab >/dev/null
LABEL=root  /      ext4  defaults,noatime  0 1
LABEL=LABBOOT /boot vfat  defaults          0 2
EOF

# boot パーティションへ: ブートローダ + kernel + initramfs
sudo cp -a mnt-root/boot/. mnt-boot/ 2>/dev/null || true
sudo cp -a mnt-root/usr/share/raspberrypi/boot/. mnt-boot/ 2>/dev/null || true
cat <<'EOF' | sudo tee mnt-boot/config.txt >/dev/null
arm_64bit=1
kernel=vmlinuz-rpi
initramfs initramfs-rpi
enable_uart=1
EOF
# USB SSD ブート前提。実測 (全 Pi 同一) の cmdline を踏襲する:
# usb-storage.quirks=7825:a2a4:u は使用中の USB-SATA アダプタの UAS 無効化、
# cgroup_enable 群はファームウェア既定の cgroup_disable=memory を後勝ちで打ち消す
echo "root=LABEL=root modules=sd-mod,usb-storage,ext4 quiet rootfstype=ext4 usb-storage.quirks=7825:a2a4:u cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1 console=tty1 console=serial0,115200" \
  | sudo tee mnt-boot/cmdline.txt >/dev/null

cleanup; trap - EXIT
zstd -19 -T0 "$IMG" -o "$IMG.zst" && rm "$IMG"
./image/encrypt-image.sh "$IMG.zst"
echo "OK: $IMG.zst.age"
