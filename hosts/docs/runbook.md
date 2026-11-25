# Runbook

方針: 人がやるのは「PR をマージする」と「台を焼いて電源を入れる」だけ。
それ以外 (k3s の導入・join、設定の収束、OS / k3s の更新、秘密の配布) は
自動で行われる。手で何かを流すのはトラブル時に限る。

## 初回セットアップ (1回だけ)

1. Terraform が GitHub に書くための fine-grained PAT を作る
   (Repository access: この repo のみ / Permissions: Administration,
   Secrets, Variables をそれぞれ Read and write)。repo シークレット
   `TF_GITHUB_TOKEN` に登録する
2. この PR をマージすると deploy workflow の terraform apply が
   - Environment `hosts` (main からのみ使用可、reviewer なし) を作り
   - `HOSTS_SSH_KEY` / `K3S_TOKEN` と変数 `HOSTS_KNOWN_HOSTS` を書く
   - repo シークレット `CF_ACCESS_CLIENT_ID` / `_SECRET` を Terraform 生成の
     サービストークンで書く (人は触らない。以前は fetch-tokens.sh が書いて
     いたが、Terraform 管理外の API 経路と食い違って deploy を壊した)
   - k3s API の新経路 `k3s-api.riya.work` (トンネル・DNS・Access) を作る。
     コネクタは server を新 image で焼いたときに入る。それまで CI は旧経路
     `lab-k3s-api.riya.work` にフォールバックする
3. Settings → Actions → General の "Allow GitHub Actions to create and
   approve pull requests" を有効にする (host-update-check の bot PR 用)
4. 全台を新 image で焼き直したら、旧 API 経路 (`lab-k3s-api.riya.work` の
   Access アプリ・DNS・トンネルと node1 の手動 cloudflared) を Zero Trust の
   画面から消す (どこにもコード化されていないため)
5. 旧方式の残骸を消す: Environment `host-ops` と `image-release`、
   シークレット `AGE_RECIPIENT` / `LAB_ADMIN_SSH_KEY` / `KUBECONFIG_B64`、
   Mac の `~/.config/lab-hosts-age.txt` と `~/.config/lab-hosts-cf/`

## 新規ノード追加 / 台交換 / 全台作り直し

1. `sh hosts/flash/fetch-tokens.sh` (Terraform state から台ごとの秘密を取り出す。
   初回と、Terraform で鍵を作り直したときだけ)
2. Release (main へのマージで自動発行) から image と `.sha256` を落とす
3. Pi (USB SSD): `hosts/flash/flash.sh --node <node> --image <...img.zst> --device <disk>`
   mini PC: 下の「mini PC」
4. 電源を入れる。以上。

あとは Host converge (6時間ごと) が台を見つけて k3s を入れ、join させる。
急ぐなら Actions の Host converge を手動実行する (`limit` に台名)。

k3s_node ロールの判定:
- k3s が動いている server が居れば、そこへ join する。焼き直した台が同じ名前で
  戻る場合は、古い Node と node-password の記録を先に消してから join する
- server が1台も動いていなければ、node1 だけが cluster-init する
  (全台作り直しは node1 から順に入る。agent は server が立った次の回で入る)
- 既に k3s が入っている台には何もしない (版上げは SUC が担当)

ホスト鍵は Terraform が台ごとに固定で持っているので、焼き直しても
known_hosts の作り直しは要らない。

## mini PC (内蔵 SSD が取り出せない台)
`flash/install-mini-pc.sh --node node1 --image <...img.zst> --usb-device /dev/disk6`

1. スクリプトが USB メモリに image を書く (macOS なら node.conf も自動注入)
2. mini PC を USB 起動する (BIOS のブートメニューで USB を選択)。
   初回起動処理で固定 IP が付き、SSH できる状態になる
3. スクリプトが内蔵ディスクの一覧を出して確認を取り、image を SSH 越しに
   dd で流す (内蔵は起動元ではないので実行中でも安全に書ける)
4. 内蔵側 EFI 領域へ node.conf を書き、自動で電源を切る
5. USB を抜いて電源 ON → 内蔵から初回起動。以後は通常手順と同じ

## 日常の変更

| やりたいこと | やり方 |
|---|---|
| ホストの設定を変える | `hosts/ansible` を直す PR をマージ → Host converge が全台へ流す |
| image を変える | `hosts/image` を直す PR をマージ → image と Release が自動で出る (適用は焼き直し) |
| k3s を上げる | bot (host-update-check) の PR をマージ → SUC が1台ずつ上げる |
| Alpine のパッチを今すぐ当てる | Actions の Host OS update を手動実行 → SUC が1台ずつ drain → 更新 → 再起動 |

週次の自動処理: SUC alpine-os (日曜 03:00、パッケージ更新 + 再起動)、
host-update-check (月曜、k3s / Alpine の新版を PR に)。

## ロールバック
image は Release 単位で不変。前の Release の image を焼き直すのがロールバック。
Ansible や Plan の変更は Git の revert をマージすれば次の収束で戻る。

## 壊れたとき (break-glass)
鍵を失った場合のみ、物理アクセスでカーネル引数に `init=/bin/sh` を足して
起動し、root シェルから authorized_keys を差し替える (root はパスワードが
ロック済みなので、シングルユーザーモードではログインできない)。

- Pi: SSD を Mac に挿し、FAT 領域の `cmdline.txt` の行末に ` init=/bin/sh` を足す
- mini PC: 起動時の systemd-boot メニューで `e` を押し、options の末尾に
  ` init=/bin/sh` を足して Enter

シェルでは `mount -o remount,rw /` してから作業し、終わったら `sync` して
電源を切り、Pi は cmdline.txt を元に戻す。**この手順は未演習**なので、
最初に使う前に node7 で一度試すこと。使ったらこの repo に issue を残すこと
(監査の代替)。

## CI の SSH 鍵を作り直す (漏洩時)
Mac で `terraform -chdir=terraform apply -replace=tls_private_key.hosts_ci` を
実行すると新しい鍵が GitHub に入るが、既存の台の authorized_keys は旧公開鍵のまま。LAN の Mac から
各台の `/home/riya/.ssh/authorized_keys` の2行目を `fetch-tokens.sh` が書いた
`nodeN.env` の `SSH_PUBKEY_CI` に差し替える (または焼き直す)。

## 注意
- Host converge は main からしか秘密に触れない。`pull_request` トリガーを
  足さないこと。fork PR の workflow 承認必須も有効のままにしておく
- 6時間ごとの Host converge は、電源の落ちている台があると失敗として通知される
  (他の台の収束は続く)。意図して止めている台は無視してよい
