#!/bin/sh
# alpine-make-vm-image / build-rpi.sh 共通の chroot 内仕上げ。
# overlay で入れたファイルに対するサービス有効化と権限だけを行う。
set -eu

# 管理ユーザー (鍵は overlay で配置済み)
id riya >/dev/null 2>&1 || adduser -D -s /bin/sh riya
addgroup riya wheel || true
chmod 700 /home/riya/.ssh && chmod 600 /home/riya/.ssh/authorized_keys
chown -R riya:riya /home/riya

# サービス有効化
for svc in sshd nftables ntpd cgroups node-firstboot; do
  rc-update add "$svc" default || rc-update add "$svc" boot
done
rc-update add networking boot || true

# 供給元記録: この image に入っているパッケージの版一覧
mkdir -p /etc/lab
apk info -v > /etc/lab/packages.manifest

# sshd は鍵のみ (drop-in が本体)
passwd -l root || true
echo "chroot configure done"
