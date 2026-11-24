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
| config | `ansible/` | k3s 導入・join、sysctl、時刻同期、監視系など起動後の desired state 全て |
| cluster | 既存 `lab` repo | Flux 以降は従来通り。ここはホスト層だけ |

## image 生成方式 (調査済み 2026-11-25)

- **x86_64 (node1-3, mini PC)**: Alpine 公式 `alpine-make-vm-image` v0.13.3
  (sha1 固定で取得)。UEFI / EFI-stub、raw image。GitHub Actions 上で約32秒という
  公式実績があり、KVM 不要なので hosted runner でそのまま動く。
- **aarch64 (node4-7, Raspberry Pi)**: 公式 rpi tarball は diskless 配布で
  x86 (ext4 の sys モード) と運用形態が揃わないため使わない。ネイティブ arm
  runner (`ubuntu-24.04-arm`、公開 repo なら 4vCPU/16GB が無料・無制限) 上で
  `apk-tools-static` により ext4 root を sys モード構築し、boot は FAT に
  raspberrypi-bootloader + linux-rpi を配置する自前アセンブリ。world と
  overlay は x86 と完全共通にしてドリフトを作らない。初回は node7 実機での
  起動確認までを「未検証の前提」とし、詰まったら runbook 側に記録する。
- 両 arch とも成果物は `.img.zst` + `.sha256` を Release に添付し、
  `actions/attest-build-provenance` で来歴を付ける。パッケージの版一覧は
  image 内 `/etc/lab/packages.manifest` に残る (SBOM 代替)。

## 使い方

```sh
# 1. image を作る: Actions の Build images を手動実行 or v* タグ
# 2. Release から image と sha256 を取得し検証
zstd -d alpine-3.24.4-x86_64.img.zst
sha256sum -c alpine-3.24.4-x86_64.img.sha256

# 3. 焼く (対象ディスクを間違えると死ぬので flash.sh は確認を挟む)
./hosts/flash/flash.sh --node node7 --image alpine-3.24.4-aarch64.img --device /dev/disk6

# 4. 起動して疎通確認後、Ansible で構築
cd hosts/ansible
ansible-playbook site.yml --limit node7        # ホスト収束
ansible-playbook bootstrap-cluster.yml          # 初回のみ: クラスタ全体
```

## 公開リポジトリとして運用する

この repo は公開する前提で線引きする (詳細は `SECURITY.md`)。

- **入れてよい**: SSH 公開鍵、192.168.1.0/24 の IP 割当、ホスト名、world。
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
- SSH は公開鍵のみ。公開鍵は `image/overlay/home/riya/.ssh/authorized_keys` に
  コミットしてよい (公開鍵は秘密ではない)。秘密鍵は Mac 側だけ。
- GitHub Secrets は image 生成に不要。使うのは Release 発行権限のみ。

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

## 未確定 (要判断)

1. agent の join 先: 現行は node1 の IP 固定。今回は DNS 名
   `api.k3s.riya.work` (3台 CP を返す) に寄せる案を group_vars に入れてある。
   join は起動時の一度きりの依存なので、ダメなら node1 固定に戻すだけ。
2. sysctl 99-ssd.conf は現行 x86 のみにあり Pi に無い (逆転疑惑)。
   Ansible では全台共通に統一してある。Pi の USB SSD 実測で問題が出たら分ける。
