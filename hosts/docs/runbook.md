# Runbook

## 新規ノード追加 / 台交換
1. Actions で image をビルド (または直近 Release を流用)
2. ディスクを取り出せる台 (Pi の USB SSD): `flash/flash.sh` で書き込み + node.conf 注入
3. 起動 → `ssh riya@<ip>` 疎通
4. `ansible-playbook site.yml --limit <node>`
5. agent なら join は bootstrap の該当 play を単体実行

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
鍵を失った場合のみ、モニタ直結で root コンソール (パスワードはロック済みなので
シングルユーザーモード) から authorized_keys を差し替える。手順を使ったら
この repo に issue を残すこと (監査の代替)。

## GitHub からホスト OS を変更する (パッケージ更新 / 再起動)

Actions の **Host ops** を手動実行する。入力は operation
(package-update / reboot / update-and-reboot) と target
(node7 単体 → agents → servers のリング順を想定)。

- 実行経路: GitHub-hosted runner が **Cloudflare Tunnel (Access SSH)
  経由** でホストに SSH する (self-hosted runner は使わない)。
  承認と秘密は Environment `host-ops` に集約: required reviewers の
  承認が無いと始まらず、SSH 秘密鍵・kubeconfig は Environment
  シークレットとして承認済みジョブにしか渡らない
- 再起動は drain → reboot → uncordon → Ready 確認まで playbook が
  面倒を見て、`serial: 1` で必ず1台ずつ
- 既存の system-upgrade-controller の週次 Plan (日曜 03:00) は定期
  パッチ用に残し、こちらはオンデマンド用。同じ台に同時にかち合う
  使い方はしない
- 版の検知は分担: Actions とコンテナ image は Dependabot、k3s と
  Alpine のピンは週次 workflow (host-update-check) が PR を作る

### Cloudflare Tunnel の初期設定 (1回だけ)

ホスト側は image 同梱の cloudflared が、ノード別のトンネルを張って
SSH を公開ホスト名に紐付ける。到達は Access のポリシーで制御する。

1. Zero Trust → Networks → Tunnels で、ノードごとにトンネルを作成
   する (名前は node1 〜 node7)。発行されるトークンを Mac に
   `~/.config/lab-hosts-cf/nodeN.token` として保存する。flash.sh が
   node.conf 経由で初回起動時に渡し、ホストの cf-tunnel サービスが使う
2. 各トンネルの Public Hostname に `ssh-nodeN.riya.work` →
   `ssh://localhost:22` を割り当てる
3. Access アプリケーションで ssh-node*.riya.work を保護し、
   サービストークンを許可するポリシーを付ける。GitHub Actions は
   repo シークレット `CF_ACCESS_CLIENT_ID` /
   `CF_ACCESS_CLIENT_SECRET` (既存) を cloudflared access の
   ProxyCommand 経由で使う。対人では GitHub ログインでの
   ブラウザ SSH も同じ入口で許可できる
4. Environment `host-ops` のシークレットに `LAB_ADMIN_SSH_KEY`
   (Mac の ~/.ssh/lab_admin の中身) と `KUBECONFIG_B64`
   (`base64 -i ~/.kube/config` の出力) を登録する

注意: Host ops は workflow_dispatch 専用。pull_request トリガーを
足さないこと (承認なしに Environment シークレットへ到達する経路を
作らないため)。fork PR workflow の承認必須も有効のままにしておく。
