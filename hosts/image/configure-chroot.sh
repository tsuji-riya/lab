#!/bin/sh
# alpine-make-vm-image / build-rpi.sh 共通の chroot 内仕上げ。
# overlay で入れたファイルに対するサービス有効化と権限だけを行う。
set -eu

# 管理ユーザー (鍵は overlay で配置済み)
id riya >/dev/null 2>&1 || adduser -D -s /bin/sh riya
addgroup riya wheel || true
chmod 700 /home/riya/.ssh && chmod 600 /home/riya/.ssh/authorized_keys
chown -R riya:riya /home/riya

# サービス有効化 (実測: cgroups / iscsid / local は全台 default)
# nftables と node-firstboot は新規分。k3s / k3s-agent は導入時に有効化される
for svc in sshd nftables ntpd cgroups iscsid local node-firstboot; do
  rc-update add "$svc" default || rc-update add "$svc" boot
done
rc-update add networking boot || true

# 供給元記録: この image に入っているパッケージの版一覧
mkdir -p /etc/lab
apk info -v > /etc/lab/packages.manifest

# sshd は鍵のみ (drop-in が本体)
passwd -l root || true

# SSH ホスト鍵は image に焼かない。apk の post-install が chroot 内で
# 生成してしまうため、ここで必ず消す。初回起動時に node-firstboot が
# 台ごとに生成する (全台同一のホスト鍵 + 公開 image は impersonation の温床)
rm -f /etc/ssh/ssh_host_*
echo "chroot configure done"
