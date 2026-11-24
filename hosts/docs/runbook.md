# Runbook

## 新規ノード追加 / 台交換
1. Actions で image をビルド (または直近 Release を流用)
2. ディスクを取り出せる台 (Pi の USB SSD): `flash/flash.sh` で書き込み + node.conf 注入
3. 起動 → `ssh-keygen -R <ip>` (焼き直した台はホスト鍵が変わる) → `ssh riya@<ip>` 疎通
4. `ansible-playbook site.yml --limit <node>`
5. agent なら join は bootstrap の該当 play を単体実行
   (`ansible-playbook bootstrap-cluster.yml --limit node1,<node>`。
   Longhorn の既定ディスク用ラベル・注釈もここで付く)
6. ホスト鍵が変わったので、Environment `host-ops` の `HOST_OPS_KNOWN_HOSTS`
   を作り直す (下の「Cloudflare Tunnel の初期設定」2.)

## mini PC (内蔵 SSD が取り出せない台)
`flash/install-mini-pc.sh --node node1 --image <...img.zst.age> --usb-device /dev/disk6`

1. スクリプトが USB メモリに image を書き、node.conf のコピーを案内する
2. mini PC を USB 起動する (BIOS のブートメニューで USB を選択)。
   初回起動処理で固定 IP が付き、SSH できる状態になる
3. スクリプトが内蔵ディスクの一覧を出して確認を取り、Mac 側で復号した
   image を SSH 越しに dd で流す (age 秘密鍵は Mac から出ない。
   内蔵は起動元ではないので実行中でも安全に書ける)
4. 内蔵側 EFI 領域へ node.conf をコピーし、自動で電源を切る
5. USB を抜いて電源 ON → 内蔵から初回起動。以後は通常手順と同じ

## 全台作り直し (今回の方式)
データ移行なしが前提。順序: image 生成 → 全台 flash → node1 起動 →
`bootstrap-cluster.yml` → この repo の Flux を流し直す。

## ロールバック
image は Release 単位で不変。前の Release の image を焼き直すのがロールバック。
Ansible の変更は Git の revert = 次回収束で戻る。

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

## GitHub からホスト OS を変更する (パッケージ更新 / 再起動)

Actions の **Host ops** を手動実行する。入力は operation
(package-update / reboot / update-and-reboot) と target
(node7 単体 → agents → servers のリング順を想定)。

- 実行経路: GitHub-hosted runner が **Cloudflare Tunnel (Access SSH)
  経由** でホストに SSH し、kubectl は Access の TCP トンネル
  (`lab-k3s-api.riya.work`) 経由で API に届く (self-hosted runner は使わない)。
  承認と秘密は Environment `host-ops` に集約: required reviewers の
  承認が無いと始まらず、CI 用 SSH 秘密鍵・known_hosts・kubeconfig は
  Environment シークレットとして承認済みジョブにしか渡らない
- 更新も再起動も `serial: 1` で1台ずつ。再起動は drain → reboot →
  Ready 確認 → uncordon。drain が失敗したら (Longhorn の退避待ちの
  タイムアウトなど) その場で止まり、再起動しない
- 既存の system-upgrade-controller の週次 Plan (日曜 03:00) は定期
  パッチ用に残し、こちらはオンデマンド用。同じ台に同時にかち合う
  使い方はしない
- 版の検知は分担: Actions とコンテナ image は Dependabot、k3s と
  Alpine のピンは週次 workflow (host-update-check) が PR を作る。
  前提: Settings → Actions → General の "Allow GitHub Actions to create and
  approve pull requests" を有効にする。bot PR の lint は workflow_dispatch
  (lint_only) で自動実行され、必須チェックを満たす

### Cloudflare Tunnel の初期設定 (1回だけ)

トンネル・DNS・Access アプリとポリシー・サービストークンは
**Terraform で管理**する (`terraform/cloudflare/host_ssh.tf`)。
PR をマージすれば既存の deploy ワークフローが plan/apply する。
Zero Trust の画面で手作業する項目はない。

残る手作業は、生成された値の受け渡しだけ:

1. Mac から `sh hosts/flash/fetch-tokens.sh --gh-secrets` を1回実行
   する (terraform state へのアクセス認証が前提)。これで
   - ノード別トンネルトークンが `~/.config/lab-hosts-cf/nodeN.token`
     に落ちる (flash.sh が焼き込み時に node.conf 経由で渡す)
   - サービストークンが GitHub シークレット `CF_ACCESS_CLIENT_ID` /
     `CF_ACCESS_CLIENT_SECRET` に登録される
2. Environment `host-ops` のシークレットに以下を登録する
   (旧 `LAB_ADMIN_SSH_KEY` は本人の鍵なので削除する):
   - `HOST_OPS_SSH_KEY`: CI 専用鍵 `~/.ssh/lab_ci` の中身
     (`ssh-keygen -t ed25519 -f ~/.ssh/lab_ci -N ''` で作る。公開鍵は
     flash.sh が node.conf 経由で配る。既存の台には
     `~/.ssh/lab_ci.pub` を `/home/riya/.ssh/authorized_keys` に追記する)
   - `HOST_OPS_KNOWN_HOSTS`: 各ノードのホスト鍵を、トンネルの
     ホスト名で引ける形にしたもの。LAN 内の Mac で作る:
     `for n in 1 2 3 4 5 6 7; do ssh-keyscan -t ed25519 192.168.1.$((9+n)) 2>/dev/null | sed "s/^[^ ]*/ssh-node$n.riya.work/"; done`
     (台を焼き直すたびに作り直す。古いままだと Host ops は接続を拒否する)
   - `KUBECONFIG_B64`: `base64 -i ~/.kube/config` の出力。接続先は
     workflow が 127.0.0.1:6443 (トンネルの口) に書き換えるので LAN の
     IP のままでよい

注意: Host ops は workflow_dispatch 専用。pull_request トリガーを
足さないこと (承認なしに Environment シークレットへ到達する経路を
作らないため)。fork PR workflow の承認必須も有効のままにしておく。
