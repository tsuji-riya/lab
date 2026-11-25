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
PR merge (唯一の人の判断 = 変更承認と実行承認を兼ねる)
  ├─ hosts/image/** が変わった → Build host images: image 生成 + Release (sha256 / provenance)
  ├─ hosts/ansible/** が変わった → Host converge: site.yml を全台へ push (初回構築を含む)
  └─ infrastructure/k3s-upgrade の版 → Flux → SUC が1台ずつ k3s を上げる
定期: Host converge (6時間ごと、ドリフト是正と新しい台の取り込み)
      SUC alpine-os (週次、drain → apk upgrade → 再起動)
人の物理作業: 台を1回焼いて電源を入れるだけ (flash.sh)
```

GitHub Actions は LAN に届かないので、ホストへは Cloudflare Access の
ノード別トンネル経由で SSH する (push 型)。秘密 (CI の SSH 鍵、k3s token、
ホスト鍵、Access のサービストークン) は Terraform が生成し、GitHub の
Environment `hosts` へ Terraform 自身が書く。人が値をコピーする作業は無い。

## レイヤ分担

| 層 | 担当 | 中身 |
|---|---|---|
| image | `image/` + Actions | Alpine 3.24、パッケージ world、鍵のみ sshd、管理ユーザー、nftables 既定拒否、first-boot |
| identity | `flash/` + Terraform | ノード固有値 (hostname / IP / role) と台ごとの秘密 (ホスト鍵・トンネル token) は image に焼かず書き込み時に注入。秘密は Terraform が生成する。image は arch ごとに1種類だけ |
| config | `ansible/` + Host converge | k3s 導入・join (自動判定)、sysctl、時刻同期など起動後の desired state。image と共通のファイルは overlay を正本として再配布する (中身を書き写さない) |
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
- 両 arch とも成果物は `.img.zst` + その `.sha256` を Release に添付し、
  `actions/attest-build-provenance` で来歴を付ける。image には設計上
  シークレットが入らない (鍵と token は焼き込み時に node.conf で入る) ため
  暗号化はしない。以前の age 暗号化は何も守らないまま、Mac での復号と
  秘密鍵のバックアップを人に強いていたので廃止した。パッケージの版一覧は
  image 内 `/etc/lab/packages.manifest` に残る (SBOM 代替)。

## 使い方

日常の変更は PR を作ってマージするだけ。以下は台を (焼き直し含め) 用意するとき。

```sh
# 1. 台ごとの秘密を Terraform state から取り出す (R2 の認証情報が要る。初回と
#    Terraform で鍵を作り直したときだけ)
sh hosts/flash/fetch-tokens.sh

# 2. Release から image と sha256 を落として焼く (sha256 は flash.sh が検証する)
./hosts/flash/flash.sh --node node7 --image alpine-3.24.4-aarch64.img.zst --device /dev/disk6

# 3. 電源を入れる。k3s の導入・join は Host converge が行う
#    (6時間以内に自動。急ぐなら Actions の Host converge を手動実行)
```

LAN から手で流す場合 (トラブル時):

```sh
set -a; . ~/.config/lab-hosts/k3s.env; set +a
cd hosts/ansible && ansible-playbook site.yml --limit node7
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
  - 実行承認ゲート (Environment の required reviewers) は置かない。
    承認は PR のマージに一本化し、Environment `hosts` は「main からしか
    使えない」制限だけを持つ (Terraform 管理: `terraform/hosts.tf`)
  - Dependabot を有効化 (Actions と apk は手動追随にしない)

## シークレットの置き方

人が値を扱わないことを原則にしている。生成は全部 Terraform (`terraform/hosts.tf`)。

| 秘密 | 生成 | CI への配布 | ノードへの配布 |
|---|---|---|---|
| k3s クラスタ token | `random_password` | Environment `hosts` の `K3S_TOKEN` (Terraform が書く) | Host converge が導入時に `K3S_TOKEN` 環境変数で渡す |
| CI の SSH 鍵 | `tls_private_key` | `HOSTS_SSH_KEY` (同上) | 公開鍵を node.conf で配る |
| ノードの SSH ホスト鍵 | `tls_private_key` (台ごと) | 公開鍵を変数 `HOSTS_KNOWN_HOSTS` に | 秘密鍵を node.conf で配る (焼き直しても不変) |
| Cloudflare トンネル token | Cloudflare provider | ― | node.conf で配る |
| Access サービストークン | Cloudflare provider | `HOSTS_CF_ACCESS_CLIENT_*` (Terraform が書く) | ― |

- 人が1度だけやること: Terraform が GitHub に書くための fine-grained PAT
  (この repo のみ、Administration / Secrets / Variables: Read and write) を作り、
  repo シークレット `TF_GITHUB_TOKEN` に登録する。GITHUB_TOKEN はシークレットを
  書けないので、ここだけは人が鍵を渡す必要がある
- node.conf は秘密を含むので、Mac 側は本人だけが読める一時ファイルに置いて
  注入後に消し、ノード側は初回起動処理が適用後に消す
- 本人の SSH 鍵 (`~/.ssh/lab_admin`) は CI とは別。CI の鍵だけを失効できる
- 生成物は Terraform state (R2) に入る。state はもともとトンネル token を
  持っているので、守るべき境界は変わらない

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
- Alpine: image ビルドの既定版。bot の PR をマージすると image が自動で
  再ビルドされる。適用は焼き直し (A/B 更新は次段で導入予定)。
  日々のパッケージ更新は SUC の alpine-os Plan (週次) と Host OS update (随時)。

## 決定済み (旧「未確定」)

1. join 先は「その時点で k3s が動いている server」の IP を k3s_node ロールが
   自動で選ぶ。1台も居なければ node1 だけが cluster-init する。DNS 名
   (3台 CP を返す名前) はレコード管理と `--tls-san` が増えるわりに利点が
   「起動時一度きりの依存」だけなので見送った。
2. sysctl 99-ssd.conf は現行 x86 のみにあり Pi に無い (逆転疑惑)。
   image / Ansible とも全台共通に統一してある。Pi の USB SSD 実測で問題が
   出たら分ける (未検証)。
