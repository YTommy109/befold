#!/usr/bin/env bash
set -euo pipefail

# ステージされた Swift ファイルがあれば SwiftFormat の lint を実行する。
# CI の build-and-test ジョブと同じチェックをコミット時点で検知するための
# pre-commit フック用スクリプト。

cd "$(git rev-parse --show-toplevel)"

if ! git diff --cached --name-only --diff-filter=ACM | grep -q '\.swift$'; then
  exit 0
fi

cd BefoldApp
swift package plugin --allow-writing-to-package-directory swiftformat -- --lint
