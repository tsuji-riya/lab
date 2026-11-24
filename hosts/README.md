# hosts (in tsuji-riya/lab)

ベアメタルから全てをコードで定義する、7台の Alpine ホストの唯一の正本。
置き場所は独立 repo ではなくこの `lab` repo の `hosts/` ディレクトリ。
クラスタ層 (Flux / Terraform) と同じ PR フローで、k3s の版上げのような
「ホストとクラスタを跨ぐ変更」を1つの PR に原子的にまとめられるのが利点。

Flux の同期パス (fluxcd/, infrastructure/, apps/) には含まれないため、
ここを変更してもクラスタには一切デプロイされない。既存 workflow
(deploy, image-scan) も paths フィルタで hosts/** では発火しない。

旧環境から移行するデータは無い。前提は「ホストは使い捨て、定義は Git」。

## 全体像

```
PR merge (変更承認)
  └─ GitHub Actions: OS image 生成 (x86_64 / aarch64)
       └─ Release + Environment 承認 (実行承認) ─ sha256 / provenance 付き
            └─ flash.sh: image をディスクへ書き込み + ノード identity 注入
                 └─ 初回起動: first-boot が hostname / 静的IP / rootfs 拡張を適用
                      └─ Ansible: クラスタ構築 (k3s server×3 → agent×4) と day-2 収束
```

GitHub Actions は LAN に到達できないので、Actions の責務は image 生成まで。
書き込みと Ansible 実行は LAN 内 (りやの Mac) から行う。これが承認境界になる:
image の Release 承認 = 「この定義で焼いてよい」、flash の実行 = 「今この台にやる」。

## レイヤ分担

| 層 | 担当 | 中身 |
|---|---|---|
| image | `image/` + Actions | Alpine 3.24、パッケージ world、鍵のみ sshd、管理ユーザー、nftables 既定拒否、first-boot |
| identity | `flash/` | ノード固有値 (hostname / IP / role) は image に焼かず書き込み時に注入。image は arch ごとに1種類だけ |
| config | `ansible/` | k3s 導入・join、sysctl、時刻同期など起動後の desired state。image と共通のファイルは overlay を正本として再配布する (中身を書き写さない) |
| cluster | 既存 `lab` repo | Flux 以降は従来通り。ここはホスト層だけ |

## image 生成方式 (調査済み 2026-11-25)

- **x86_64 (node1-3, mini PC)**: Alpine 公式 `alpine-make-vm-image` v0.13.3
  (sha1 固定で取得)。UEFI、raw image。KVM 不要なので hosted runner でそのまま動く。
  VM 向けツールなので実機向けに3点を上書きしている: カーネルは `linux-lts`
  (既定の `linux-virt` は実機ドライバが乏しい)、initramfs に nvme/ata/usb を追加、
  ブートローダは systemd-boot を `EFI/BOOT/BOOTX64.EFI` に配置 (ツールは
  EFI シェル用の `startup.nsh` しか置かず、実機ファームウェアからは起動できない)。
- **aarch64 (node4-7, Raspberry Pi)**: 公式 rpi tarball は diskless 配布で
  x86 (ext4 の sys モード) と運用形態が揃わないため使わない。ネイティブ arm
  runner (`ubuntu-24.04-arm`、公開 repo なら 4vCPU/16GB が無料・無制限) 上で
  `apk-tools-static` により ext4 root を sys モード構築し、boot は FAT に
  raspberrypi-bootloader + linux-rpi を配置する自前アセンブリ。world と
  overlay は x86 と共通 (arch 固有のパッケージだけ `packages.<arch>` に分ける)。初回は node7 実機での
  起動確認までを「未検証の前提」とし、詰まったら runbook 側に記録する。
- 両 arch とも成果物は age 暗号化した `.img.zst.age` + その `.sha256` を
  Release に添付し (平文は CI 上でも Release にも残さない)、
  `actions/attest-build-provenance` で来歴を付ける。パッケージの版一覧は
  image 内 `/etc/lab/packages.manifest` に残る (SBOM 代替)。

## 使い方

```sh
# 1. image を作る: Actions の Build host images を手動実行 (Artifact で受け取る)
#    or hosts-v* タグ (Release に添付される)
# 2. Release から暗号化 image と sha256 を取得し検証
sha256sum -c alpine-3.24.4-x86_64.img.zst.age.sha256

# 3. 焼く (復号は flash.sh がパイプでやる。平文はディスクに残らない)
./hosts/flash/flash.sh --node node7 --image alpine-3.24.4-aarch64.img.zst.age --device /dev/disk6

# 4. 起動して疎通確認後、Ansible で構築
cd hosts/ansible
ansible-playbook site.yml --limit node7        # ホスト収束
ansible-playbook bootstrap-cluster.yml          # 初回のみ: クラスタ全体
```

## 公開リポジトリとして運用する

この repo は公開する前提で線引きする (詳細は `SECURITY.md`)。

- **入れてよい**: 192.168.1.0/24 の IP 割当、ホスト名、world。
  SSH 公開鍵も本来は公開して安全なものだが、この repo では念のため
  入れない設計にした (焼き込み時に node.conf 経由で注入する)。
  既存の公開 repo `lab` に既出の情報であり、公開による増分リスクはほぼ無い
- **絶対に入れない**: 秘密鍵、パスワード、k3s token、Vault 平文、実機の
  シリアル/MAC。そもそも設計上、repo に置く必要が生じないようにしてある
- **GitHub 側の設定 (公開 repo だと無料で効くもの)**:
  - secret scanning + push protection を有効化
  - ruleset "Protect main" を有効化し、PR + lint 通過を必須にする
    (`lab` 側で disabled だった轍は踏まない)
  - Environment `image-release` に required reviewers + wait timer
    (公開 repo では無料枠で使える。これが実行承認ゲート)
  - Dependabot を有効化 (Actions と apk は手動追随にしない)

## シークレットの置き方

- k3s token は image にも Git にも入れない。`bootstrap-cluster.yml` が node1 で
  生成し、実行時にメモリ上でのみ各ノードへ配る。恒常保存が必要なら Ansible Vault。
- SSH は公開鍵のみ。公開鍵は Git にも image にも入れず、`flash.sh` が
  焼き込み時に Mac の `~/.ssh/lab_admin.pub` (本人用) と `~/.ssh/lab_ci.pub`
  (Host ops 用) を node.conf へ埋め込み、初回起動で authorized_keys に配置する。
  CI 用の鍵を分けているのは、CI の権限だけを失効できるようにするため。
  node.conf はトンネル token を含むので、初回起動処理が適用後に削除する。
  鍵を差し替えても image の再ビルドは不要になる利点もある。
- GitHub Secrets は image 生成に不要。使うのは Release 発行権限のみ。
- image の暗号化は age。公開鍵は repo に置かず、Actions Secret の
  `AGE_RECIPIENT` に登録する (Settings → Secrets and variables → Actions
  からいつでも上書き可能、コミット不要)。秘密鍵は Mac の
  `~/.config/lab-hosts-age.txt` にだけ置く。生成は一度だけ:
  `age-keygen -o ~/.config/lab-hosts-age.txt` (Mac に age が無ければ
  `brew install age`)。秘密鍵を失うと過去の Release image は全部復号不能になる
  ので、パスワードマネージャ等にバックアップすること。

## 現行ホスト実測から取り込んだ改変 (2026-11-25、全7台調査)

忘れていた「ちょっとした修正」の正体はこれだった。全台共通分は image の
overlay と Ansible base ロールに取り込み済み。

- `cgroups` サービスを default で有効化。cgroup は全台 cgroup2 統一
  (v1 混在や rc.conf の追加設定は無し)
- `/etc/local.d/rshared.start` で `mount --make-rshared /` (Longhorn の伝播)
- `/etc/modules` = af_packet, ipv6, iscsi_tcp, dm_crypt
- `iscsid` 有効化 + world に open-iscsi / nfs-utils (Longhorn の前提)
- Pi の cmdline: `usb-storage.quirks=7825:a2a4:u` (USB-SATA の UAS 無効化) と
  `cgroup_enable=cpuset cgroup_enable=memory cgroup_memory=1`
  (ファームウェア既定の cgroup_disable=memory を後勝ちで打ち消す)
- fstab の tmpfs 2件 (/tmp 256m、/var/log 64m)
- 台固有: node1 のみ cloudflared 常駐。実測で見えた /var/lib/longhorn-hdd
  マウントは、対象 HDD が既に撤去済みのため取り込まなかった
  (2026-11-25 本人申告。台固有マウントの仕組みだけ base ロールに残してある)

実測との意図的な差分: smartmontools は node2/3/5/6 に無いドリフトだったので
全台統一で入れる。sysctl 99-ssd.conf は x86 のみに実在したが全台統一のまま。
/etc/hosts の `nodeN.my.domain` は setup-alpine の下書き残りと判断し、
first-boot が正しい FQDN で書く形にした。

## 版の正本

- k3s: 稼働中の版は SUC の Plan (`infrastructure/k3s-upgrade/plan.yaml` の
  `spec.version`) が正本。`ansible/group_vars/all.yml` の `k3s_version` は
  初回インストール時だけ使う。週次の host-update-check が両方を同時に書き換える
  PR を作り、マージが版上げの承認になる (マージすると SUC が全台を上げる)。
- Alpine: image ビルドの既定版。適用は image 再ビルド + 焼き直し。
  日々のパッケージ更新は SUC の alpine-os Plan (週次) と Host ops (随時)。

## 決定済み (旧「未確定」)

1. agent / server の join 先は node1 の IP 固定。DNS 名 (3台 CP を返す名前) は、
   bootstrap 時点で生きているのが node1 だけで join が当たり外れになるのと、
   レコード管理と `--tls-san` が増えるわりに利点が「起動時一度きりの依存」だけ
   なので見送った。
2. sysctl 99-ssd.conf は現行 x86 のみにあり Pi に無い (逆転疑惑)。
   image / Ansible とも全台共通に統一してある。Pi の USB SSD 実測で問題が
   出たら分ける (未検証)。
