# Runbook

## 新規ノード追加 / 台交換
1. Actions で image をビルド (または直近 Release を流用)
2. `flash/flash.sh` で書き込み + node.conf 注入
3. 起動 → `ssh riya@<ip>` 疎通
4. `ansible-playbook site.yml --limit <node>`
5. agent なら join は bootstrap の該当 play を単体実行

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
