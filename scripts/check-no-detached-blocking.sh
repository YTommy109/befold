#!/usr/bin/env bash
set -euo pipefail

# Swift コードに `Task.detached` が現れないことを確認する。
#
# なぜ機械で止めるか（TASK-424 / TASK-427 / TASK-516 の実測）:
# `Task.detached` は Swift 並行の協調スレッドプールの上で走る。プールの幅はコア数で
# 固定されているため、subprocess の待ち・ファイル I/O・テストの意図的な足止めのように
# **同期的に塞ぐ**処理を置くと、幅ぶんの同時ブロックでプロセス全体の前進が止まる。
# 症状は「全スイート pass なのに «unknown» issue で run が exit 1」という、
# 失敗テスト名の出ない形で現れる。規約として 3 度書いても 3 度破れたため機械で止める。
#
# 代わりに `withBlockingWork`（BefoldApp/BefoldKit/BlockingWork.swift）を使う。
# 専用スレッドで実行するため、塞いでも他の仕事の前進を止めない。

ROOT="$(git rev-parse --show-toplevel)"
PATTERN='Task\.detached[[:space:]]*[({]'

# grep で検索する（rg は GitHub Actions の ubuntu ランナーに入っていない。
# rg 前提で書いたところ `rg: command not found` で 0 件になり、self-test が
# 「検知できていない」を出して落ちた。検査自体を素通りさせないため常在する grep を使う）。
run_check() {
  local target="$1"
  grep -rnE --include='*.swift' --exclude-dir='.build' -e "$PATTERN" "$target" || true
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  printf 'let t = Task.detached { 1 }\n' > "$tmp/Sample.swift"
  if [[ -z "$(run_check "$tmp")" ]]; then
    echo "self-test 失敗: Task.detached を検知できていない" >&2
    exit 1
  fi
  echo "self-test OK: Task.detached を検知できる"
  exit 0
fi

hits="$(run_check "$ROOT/BefoldApp")"
if [[ -n "$hits" ]]; then
  echo "Task.detached は使わない（協調スレッドプールを塞ぐ）。withBlockingWork を使うこと:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "OK: Task.detached の使用なし"
