#!/usr/bin/env bash
set -euo pipefail

# main ブランチへの直接コミットをブロックする。
# リリース系スクリプト(scripts/bump.sh、/release の CHANGELOG コミット)は
# 意図的に main へコミットするため、ALLOW_MAIN_COMMIT=1 を設定して呼び出す
# ことでこのチェックを通過する。
BRANCH="$(git rev-parse --abbrev-ref HEAD)"
if [ "$BRANCH" = "main" ] && [ "${ALLOW_MAIN_COMMIT:-}" != "1" ]; then
  echo "エラー: main ブランチへの直接コミットはブロックされています。" >&2
  echo "  作業用ブランチを作成してください: git checkout -b <branch-name>" >&2
  echo "  意図的に main へコミットする場合は ALLOW_MAIN_COMMIT=1 git commit ... としてください。" >&2
  exit 1
fi
