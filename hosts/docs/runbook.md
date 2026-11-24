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

- 実行は Mac 上の self-hosted runner (label `lab-lan`) が Ansible
  `ops.yml` を叩く形。GitHub-hosted runner は LAN に届かないため
- Environment `host-ops` の承認が実行ゲート。再起動は drain →
  reboot → uncordon → Ready 確認まで playbook が面倒を見て、
  `serial: 1` で必ず1台ずつ
- 既存の system-upgrade-controller の週次 Plan (日曜 03:00) は定期
  パッチ用に残し、こちらはオンデマンド用。同じ台に同時にかち合う
  使い方はしない

### self-hosted runner の初期設定 (Mac、1回だけ)

1. repo の Settings → Actions → Runners → New self-hosted runner
   (macOS) の手順で `~/actions-runner` に展開し、`./config.sh` で
   label `lab-lan` を付けて登録
2. `./svc.sh install && ./svc.sh start` で常駐化 (launchd)
3. runner が使う SSH 鍵は Ansible と同じ `~/.ssh/lab_admin`。
   kubeconfig は drain 用に `~/.kube/config` を置く
4. Environment `host-ops` を作り、自分を required reviewer にする

注意: **公開 repo + self-hosted runner の組み合わせは、fork PR の
workflow を runner で実行させないことが絶対条件**。Host ops は
workflow_dispatch 専用にしてあり、pull_request トリガーを足さない。
GitHub 側でも Settings → Actions → "Fork pull request workflows"
の承認必須を有効にしておく。
