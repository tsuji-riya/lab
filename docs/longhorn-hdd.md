# Longhorn HDD ディスク構成

node1 の HDD を Longhorn のディスクとして追加し、SSD と HDD で StorageClass を分けている。

## 構成

| 項目 | 内容 |
| --- | --- |
| HDD | node1.k3s.riya.work の `/dev/sdb`(916G、ext4、ラベル `longhorn-hdd`) |
| マウント先 | `/var/lib/longhorn-hdd`(fstab 登録済み) |
| Longhorn ディスク名 | `hdd-disk`(node1 の Node CR) |
| ディスクのタグ | HDD は `hdd`、node1〜3 の既存 SSD(`/var/lib/longhorn/`)は `ssd` |
| storageReserved | HDD は 49000000000 bytes(約 5%)、SSD は既定のまま(約 30%) |

## StorageClass

| 名前 | diskSelector | レプリカ数 | reclaimPolicy | 用途 |
| --- | --- | --- | --- | --- |
| `longhorn`(default) | `ssd` | 3 | Delete | 通常用途。SSD のみに配置 |
| `longhorn-hdd` | `hdd` | 1 | Delete | 大容量・低速でよいデータ。レプリカは node1 の HDD |

- `longhorn` の `diskSelector` は HelmRelease の `persistence.defaultDiskSelector` で設定している([helmrelease.yaml](../infrastructure/longhorn/helmrelease.yaml))。
- `longhorn-hdd` は [storageclass-hdd.yaml](../infrastructure/longhorn/storageclass-hdd.yaml)。
- `longhorn-hdd` のボリュームは node1 以外の Pod からも使える(データ本体は node1 にあり、ネットワーク越しにアクセスする)。

## Git 管理外の設定

Node CR は Longhorn が生成するリソースのため Git では管理していない。次の設定は `kubectl patch` で直接適用した。クラスタや Longhorn を作り直したときは再実行すること。

```bash
# 既存 SSD ディスクに ssd タグを付ける(ディスクのキーは `kubectl -n longhorn-system get nodes.longhorn.io <node> -o yaml` で確認)
kubectl -n longhorn-system patch nodes.longhorn.io node1.k3s.riya.work --type=json -p '[{"op":"replace","path":"/spec/disks/<node1 の既存ディスクキー>/tags","value":["ssd"]}]'
kubectl -n longhorn-system patch nodes.longhorn.io node2.k3s.riya.work --type=json -p '[{"op":"replace","path":"/spec/disks/<node2 の既存ディスクキー>/tags","value":["ssd"]}]'
kubectl -n longhorn-system patch nodes.longhorn.io node3.k3s.riya.work --type=json -p '[{"op":"replace","path":"/spec/disks/<node3 の既存ディスクキー>/tags","value":["ssd"]}]'

# node1 に HDD ディスクを追加する(既存ディスクのエントリには触れない)
kubectl -n longhorn-system patch nodes.longhorn.io node1.k3s.riya.work --type=json -p '[{"op":"add","path":"/spec/disks/hdd-disk","value":{"path":"/var/lib/longhorn-hdd","diskType":"filesystem","allowScheduling":true,"evictionRequested":false,"storageReserved":49000000000,"tags":["hdd"]}}]'
```

注意:
- Node CR の `spec.disks` は map なので、JSON patch の `add`/`replace` でキー単位に更新する。merge patch で配列全体を置き換えない。
- `ssd` タグが無いディスクには、`longhorn` SC のボリュームを配置できない。

## StorageClass の変更手順

StorageClass の parameters は作成後に変更できない。`longhorn` SC の `diskSelector` を変えるときは、SC を削除して Longhorn に作り直させる。既存の PV/PVC/ボリュームには影響しない。

```bash
kubectl delete sc longhorn
kubectl -n longhorn-system rollout restart deploy/longhorn-driver-deployer
```

## 注意点

- `longhorn-hdd` はレプリカが 1 つ。node1 の停止や HDD の故障でボリュームが使えなくなり、データを失うおそれがある。重要なデータにはバックアップを設定する。
- reclaimPolicy が Delete なので、PVC を削除するとデータも消える。
- `longhorn-static` SC には `diskSelector` が無い。これで動的にボリュームを作ると HDD にもレプリカが載る。
- `local-path` と `longhorn` の両方がデフォルト SC になっている。
- fstab は `/dev/sdb` ではなく UUID(`566df1e9-6169-4443-8eca-c35b479f9090`)で指定する。デバイス名は再起動で変わりうる。

## 動作確認の手順

```bash
kubectl create ns lh-hdd-test
# longhorn-hdd の PVC と、node1 以外に固定した Pod を作成して書き込みを確認
kubectl -n longhorn-system get replicas.longhorn.io -o custom-columns=NAME:.metadata.name,NODE:.spec.nodeID,DISK:.spec.diskPath
kubectl delete ns lh-hdd-test
```

レプリカの `DISK` が `/var/lib/longhorn-hdd` になっていること。
