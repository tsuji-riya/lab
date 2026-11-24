#!/bin/sh
# alpine-make-vm-image / build-rpi.sh 共通の chroot 内仕上げ。
# overlay で入れたファイルに対するサービス有効化と権限だけを行う。
set -eu

# 管理ユーザー (鍵は overlay で配置済み)
id riya >/dev/null 2>&1 || adduser -D -s /bin/sh riya
addgroup riya wheel || true
# authorized_keys は image に入れない (node.conf 経由で初回起動時に注入)。
# ここでは .ssh ディレクトリだけ用意する
mkdir -p /home/riya/.ssh
chmod 700 /home/riya/.ssh
chown -R riya:riya /home/riya

# サービス有効化 (実測: cgroups / iscsid / local は全台 default)
# nftables と node-firstboot は新規分。k3s / k3s-agent は導入時に有効化される
for svc in sshd nftables ntpd cgroups iscsid local cf-tunnel node-firstboot; do
  rc-update add "$svc" default || rc-update add "$svc" boot
done
rc-update add networking boot || true

# cloudflared は Alpine のパッケージに無いため、公式の静的バイナリを
# 版固定で入れる (現行ホストの node1 もバイナリ配置のはず)
CF_VERSION="2026.11.2"
case "$(uname -m)" in
  x86_64)  CF_ARCH=amd64 ;;
  aarch64) CF_ARCH=arm64 ;;
  *) echo "unknown arch: $(uname -m)" >&2; exit 1 ;;
esac
curl -fsSL "https://github.com/cloudflare/cloudflared/releases/download/${CF_VERSION}/cloudflared-linux-${CF_ARCH}" -o /usr/bin/cloudflared
chmod 755 /usr/bin/cloudflared

# 供給元記録: この image に入っているパッケージの版一覧
mkdir -p /etc/lab
apk info -v > /etc/lab/packages.manifest

# sudoers.d のパーミッションを正す (緩いと sudo が読み飛ばす)
chmod 440 /etc/sudoers.d/riya 2>/dev/null || true

# sshd は鍵のみ (drop-in が本体)
passwd -l root || true

# SSH ホスト鍵は image に焼かない。apk の post-install が chroot 内で
# 生成してしまうため、ここで必ず消す。初回起動時に node-firstboot が
# 台ごとに生成する (全台同一のホスト鍵 + 公開 image は impersonation の温床)
rm -f /etc/ssh/ssh_host_*
echo "chroot configure done"
