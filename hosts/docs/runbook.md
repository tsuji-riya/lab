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
