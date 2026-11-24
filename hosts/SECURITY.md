# Security Policy

この repo は公開前提で設計している。以下は repo に **入れない**:

- SSH 秘密鍵、パスワード、k3s token (token は bootstrap 実行時のメモリ上にのみ存在)
- Ansible Vault の平文、実シークレットを含む `*.local.yml`
- 実機のシリアル番号・MAC アドレスが写った写真やログ

入れてよいもの: プライベート IP 帯 (192.168.1.0/24) の構成、ホスト名、
パッケージ一覧。これらは既存の公開 repo `tsuji-riya/lab` にも既出。
SSH 公開鍵は公開しても安全なものだが、本 repo では入れない設計:
焼き込み時に Mac から node.conf 経由で注入し、初回起動で配置する。
node.conf は Cloudflare Tunnel の token を含むため、Mac 側では本人だけが読める
一時ファイルに置いて注入後に消し、ノード側では初回起動処理が適用後に消す。
Host ops (CI) の SSH 鍵は本人の鍵と分け、CI の権限だけを失効できるようにしている。
age の公開鍵は CI が必要とするため Actions Secret の `AGE_RECIPIENT` に
置く (公開鍵なので Secret 化は秘匿ではなく管理上の都合。値は上書きのみ
可能で、差し替えたら旧鍵で作られた Release は旧秘密鍵でのみ復号できる)。

混入防止は二重: GitHub の secret scanning + push protection (公開 repo は無料) と、
CI の lint job でのパターンスキャン。万一秘密を push したら「履歴から消す」ではなく
**その秘密を無効化 (鍵の差し替え / token ローテーション) する**のが正解。
