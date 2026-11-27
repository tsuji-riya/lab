#!/bin/sh
# alpine-make-vm-image / build-rpi.sh 共通の chroot 内仕上げ。
# overlay で入れたファイルに対するサービス有効化と権限だけを行う。
set -eu

# 管理ユーザー (鍵は overlay で配置済み)
id riya >/dev/null 2>&1 || adduser -D -s /bin/sh riya
addgroup riya wheel || true
# adduser -D は shadow を "!" (ロック) にするが、OpenSSH はロックされた
# アカウントを公開鍵でも拒否する。"*" にするとパスワードログイン不可の
# まま、アカウントロックだけ外れる (鍵ログインが通る)
sed -i 's/^riya:!/riya:*:/' /etc/shadow
# authorized_keys は image に入れない (node.conf 経由で初回起動時に注入)。
# ここでは .ssh ディレクトリだけ用意する
mkdir -p /home/riya/.ssh
chmod 700 /home/riya/.ssh
chown -R riya:riya /home/riya

# サービス有効化 (実測: cgroups / local は全台 default)
# nftables と node-firstboot は新規分。k3s / k3s-agent は導入時に有効化される
for svc in sshd nftables ntpd cgroups local cf-tunnel cf-tunnel.api crond; do
  rc-update add "$svc" default || rc-update add "$svc" boot
done
# identity 適用は networking より先 (boot ランレベル)
rc-update add node-firstboot boot

# 標準サービスの runlevel は openrc パッケージには含まれず、通常は
# setup-alpine が入れる。自前で rootfs を組む場合は明示的に有効化する。
# これが無いと localmount 不在で /boot がマウントされず node.conf が
# 読めない、hwdrivers/mdev 不在で USB キーボードや NIC のドライバが
# ロードされない、root 不在で / が rw 再マウントされない (node7 実機で発覚)
# 存在するサービスだけを有効化する (名前は openrc の版で変わる:
# urandom は seedrng に改名された。無い名前を rc-update すると
# set -e でビルドごと落ちるので、実在チェックを挟む)
for svc in devfs dmesg mdev; do
  [ -e "/etc/init.d/$svc" ] && rc-update add "$svc" sysinit
done
for svc in root localmount hostname sysctl modules hwdrivers bootmisc seedrng swap syslog; do
  [ -e "/etc/init.d/$svc" ] && rc-update add "$svc" boot
done
# Pi は RTC を持たない。swclock は前回停止時刻から時計を始めるので、
# ntpd が同期するまでの間に時刻が 1970 年へ戻って TLS 検証が全滅するのを防ぐ
if [ "$(uname -m)" = aarch64 ]; then
  rc-update add swclock boot
fi
rc-update add networking boot || true

# cloudflared は Alpine のパッケージに無いため、公式の静的バイナリを
# 版固定で入れる (現行ホストの node1 もバイナリ配置のはず)
# sha256 は版を上げるときに公式 release の成果物から取り直すこと
CF_VERSION="2026.11.2"
case "$(uname -m)" in
  x86_64)  CF_ARCH=amd64 CF_SHA256=56f13335143ec0e22772963290683a84a04114a35ec64cbc794a4d39ff9bb8cf ;;
  aarch64) CF_ARCH=arm64 CF_SHA256=04a7b7f08bce85d56b26ffe1fdbfbb21a074495a363d16f0783c40e25b5c5281 ;;
  *) echo "unknown arch: $(uname -m)" >&2; exit 1 ;;
esac
curl -fsSL "https://github.com/cloudflare/cloudflared/releases/download/${CF_VERSION}/cloudflared-linux-${CF_ARCH}" -o /usr/bin/cloudflared
echo "${CF_SHA256}  /usr/bin/cloudflared" | sha256sum -c
chmod 755 /usr/bin/cloudflared

# x86: 実機 UEFI が読むのはリムーバブル既定パス EFI/BOOT/BOOTX64.EFI だけ。
# alpine-make-vm-image は EFI シェル用の startup.nsh しか置かないため、
# systemd-boot をそこへ置き、カーネルを直接指すエントリを書く。
# ESP は /boot にマウントされ、kernel / initramfs も ESP 上にある。
# ファイル名は版に依存しないので apk でカーネルを上げてもエントリは不変
if [ "$(uname -m)" = x86_64 ]; then
  ROOT_SPEC=$(awk '$2 == "/" { print $1 }' /etc/fstab)
  case "$ROOT_SPEC" in
    UUID=*) ;;
    *) echo "root の UUID が fstab から引けない: $ROOT_SPEC" >&2; exit 1 ;;
  esac
  # alpine-make-vm-image は root を relatime で書く。SSD の書き込み削減のため
  # Pi (build-rpi.sh) と同じ noatime,lazytime に揃える
  sed -i -E 's|^(UUID=[^[:space:]]+[[:space:]]+/[[:space:]]+[^[:space:]]+[[:space:]]+)relatime([[:space:]])|\1noatime,lazytime\2|' /etc/fstab
  grep -Eq '^UUID=[^[:space:]]+[[:space:]]+/[[:space:]]+[^[:space:]]+[[:space:]]+noatime,lazytime[[:space:]]' /etc/fstab || { echo "root の fstab に noatime を入れられない" >&2; exit 1; }
  # build-x86.sh の --initfs-features (nvme/ata/usb) で initramfs を作り直す。
  # カーネル導入時点の initramfs は機能設定より前に作られている
  mkinitfs "$(ls /lib/modules)"
  install -D -m 644 /usr/lib/systemd/boot/efi/systemd-bootx64.efi /boot/EFI/BOOT/BOOTX64.EFI
  mkdir -p /boot/loader/entries
  printf 'default lab.conf\ntimeout 3\n' > /boot/loader/loader.conf
  {
    echo "title   Alpine Linux (lab)"
    echo "linux   /vmlinuz-lts"
    echo "initrd  /initramfs-lts"
    echo "options root=${ROOT_SPEC} rootfstype=ext4 modules=sd-mod,usb-storage,ext4,nvme quiet"
  } > /boot/loader/entries/lab.conf
fi

# 供給元記録: この image に入っているパッケージの版一覧
mkdir -p /etc/lab
apk info -v > /etc/lab/packages.manifest

# sudoers.d のパーミッションを正す (緩いと sudo が読み飛ばす)
chmod 440 /etc/sudoers.d/riya 2>/dev/null || true

# overlay の所有者は焼く側で root にしている (build-rpi.sh: --no-preserve=ownership、
# build-x86.sh: --fs-skel-chown)。ここで chown -R /etc /usr をすると、chown が
# setuid ビットを消すため sudo / su が全滅する (node7 実機で発覚、2026-11-26)

# sshd は鍵のみ (drop-in が本体)
passwd -l root || true

# SSH ホスト鍵は image に焼かない。apk の post-install が chroot 内で
# 生成してしまうため、ここで必ず消す。初回起動時に node-firstboot が
# node.conf の台ごとの鍵 (Terraform 生成) を置く (全台同一の鍵 + 公開 image は
# impersonation の温床)
rm -f /etc/ssh/ssh_host_*

# ビルド環境 (runner / docker) の resolv.conf を image に残さない。
# runner 固有の 127.0.0.53 などが焼かれると実機で名前解決できない。
# 実機の resolv.conf は node-firstboot が node.conf から書く
rm -f /etc/resolv.conf
# 自己チェック: 実機で初めて分かった失敗を build で落とす
[ -u /usr/bin/sudo ] || { echo "sudo の setuid が無い" >&2; exit 1; }
[ "$(stat -c %u /etc/sudoers.d/riya)" = 0 ] || { echo "sudoers.d/riya が root 所有でない" >&2; exit 1; }
for cmd in growpart resize2fs findmnt lsblk partx sfdisk cloudflared; do
  command -v "$cmd" >/dev/null || { echo "firstboot が使う $cmd が無い" >&2; exit 1; }
done
echo "chroot configure done"
