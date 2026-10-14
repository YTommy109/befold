#!/usr/bin/env bash
set -euo pipefail

# テストが実ユーザーのホーム直下に一時ディレクトリを作らないことを確認する(TASK-705)。
#
# なぜ機械で止めるか: ホーム直下の `befold-test-<UUID>` は TempDir の deinit で消えるが、
# テストが止まって強制終了された実行では消えずに残る(実測: 79 個)。サイドバーの
# 「ホーム配下のみ移動可」は SidebarNavigator / ViewerWindowDependencies の `home` 注入で
# 一時ディレクトリに差し替えられるので、ホームを使う理由は無い。
#
# 検知するのは `makeHomeTempDir`(撤去済み)と、ホームを base にした `TempDir(base:)`。

ROOT="$(git rev-parse --show-toplevel)"
PATTERN='makeHomeTempDir|TempDir\(base:[^)]*homeDirectoryForCurrentUser'

# rg は GitHub Actions の ubuntu ランナーに無いので grep を使う(check-no-detached-blocking.sh と同じ理由)。
run_check() {
  grep -rnE --include='*.swift' --exclude-dir='.build' -e "$PATTERN" "$1" || true
}

if [[ "${1:-}" == "--self-test" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  printf 'let a = try makeHomeTempDir()\nlet b = try TempDir(base: FileManager.default.homeDirectoryForCurrentUser)\n' > "$tmp/Sample.swift"
  if [[ "$(run_check "$tmp" | wc -l | tr -d ' ')" != "2" ]]; then
    echo "self-test 失敗: ホーム直下への一時ディレクトリ作成を検知できていない" >&2
    exit 1
  fi
  echo "self-test OK: ホーム直下への一時ディレクトリ作成を検知できる"
  exit 0
fi

hits="$(run_check "$ROOT/BefoldApp")"
if [[ -n "$hits" ]]; then
  echo "テストはホーム直下に一時ディレクトリを作らない。TempDir() を使い、ホームは home: で注入すること:" >&2
  echo "$hits" >&2
  exit 1
fi
echo "OK: ホーム直下への一時ディレクトリ作成なし"
