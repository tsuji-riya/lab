# Security Policy

この repo は公開前提で設計している。以下は repo に **入れない**:

- SSH 秘密鍵、パスワード、k3s token (秘密は Terraform が生成し、state と
  GitHub の Environment `hosts` にだけ存在する。Git にも image にも入らない)
- Ansible Vault の平文、実シークレットを含む `*.local.yml`
- 実機のシリアル番号・MAC アドレスが写った写真やログ

入れてよいもの: プライベート IP 帯 (192.168.1.0/24) の構成、ホスト名、
パッケージ一覧。これらは既存の公開 repo `tsuji-riya/lab` にも既出。
SSH 公開鍵は公開しても安全なものだが、本 repo では入れない設計:
焼き込み時に Mac から node.conf 経由で注入し、初回起動で配置する。
node.conf は Cloudflare Tunnel の token と SSH ホスト鍵を含むため、Mac 側では本人だけが読める
一時ファイルに置いて注入後に消し、ノード側では初回起動処理が適用後に消す。
Host converge (CI) の SSH 鍵は本人の鍵と分け、CI の権限だけを失効できるようにしている。
CI が秘密に触れるのは main からの実行だけ (Environment `hosts` の
ブランチ制限)。main へのマージが、ホストへ root で変更を流す唯一の入口になる。
image は暗号化しない。設計上 image にはシークレットが入らないため
(鍵と token は焼き込み時に node.conf で入る)、完全性を sha256 と
build provenance で担保すれば足りる。

混入防止は二重: GitHub の secret scanning + push protection (公開 repo は無料) と、
CI の lint job でのパターンスキャン。万一秘密を push したら「履歴から消す」ではなく
**その秘密を無効化 (鍵の差し替え / token ローテーション) する**のが正解。
