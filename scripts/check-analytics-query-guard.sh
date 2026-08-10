#!/usr/bin/env bash
set -euo pipefail

# 解析用 D1 の読み取り専用ガード（scripts/analytics-query.sh）が実効であることを
# コミット時点で確認する。ガードの判定を緩めると、拒否すべき SQL を通した時点で
# self-test が落ちる。
#
# pre-commit フックが引数を渡せない形（scripts/setup-git-hooks.sh）なので、
# --self-test を固定で呼ぶだけの薄いラッパにしてある。

ROOT="$(git rev-parse --show-toplevel)"
exec "$ROOT/scripts/analytics-query.sh" --self-test
