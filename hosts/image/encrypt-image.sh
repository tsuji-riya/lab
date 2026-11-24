#!/bin/sh
# ビルド成果物を age で暗号化し、sha256 を作り直して平文を消す。
# 使い方: ./image/encrypt-image.sh out/alpine-...-x86_64.img.zst
set -eu
cd "$(dirname "$0")/.."
TARGET="$1"

# 宛先は Actions Secret (env AGE_RECIPIENT) が正。ファイルはローカル実行時の予備
RECIPIENT="${AGE_RECIPIENT:-}"
if [ -z "$RECIPIENT" ]; then
  RECIPIENT=$(grep -E '^age1[0-9a-z]+$' image/age-recipient.txt || true)
fi
case "$RECIPIENT" in
  age1*) ;;
  *) echo "age 公開鍵 (age1...) が未設定です。CI では Secret AGE_RECIPIENT、ローカルでは env か age-recipient.txt に設定してください" >&2; exit 1 ;;
esac

command -v age >/dev/null 2>&1 || {
  sudo apt-get update -qq && sudo apt-get install -y -qq age
}

age -r "$RECIPIENT" -o "${TARGET}.age" "$TARGET"
rm "$TARGET"
( cd "$(dirname "$TARGET")" && sha256sum "$(basename "${TARGET}.age")" \
    > "$(basename "${TARGET}.age").sha256" )
echo "encrypted: ${TARGET}.age"
