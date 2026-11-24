#!/bin/sh
# ビルド成果物を age で暗号化し、sha256 を作り直して平文を消す。
# 使い方: ./image/encrypt-image.sh out/alpine-...-x86_64.img.zst
set -eu
cd "$(dirname "$0")/.."
TARGET="$1"

RECIPIENT=$(grep -E '^age1[0-9a-z]+$' image/age-recipient.txt || true)
[ -n "$RECIPIENT" ] || {
  echo "image/age-recipient.txt に age 公開鍵 (age1...) が入っていません" >&2
  exit 1
}

command -v age >/dev/null 2>&1 || {
  sudo apt-get update -qq && sudo apt-get install -y -qq age
}

age -r "$RECIPIENT" -o "${TARGET}.age" "$TARGET"
rm "$TARGET"
( cd "$(dirname "$TARGET")" && sha256sum "$(basename "${TARGET}.age")" \
    > "$(basename "${TARGET}.age").sha256" )
echo "encrypted: ${TARGET}.age"
