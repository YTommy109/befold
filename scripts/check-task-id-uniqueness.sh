#!/usr/bin/env bash
set -euo pipefail

# backlog のタスク ID がリポジトリ全体（tasks / drafts / archive / completed）で
# 一意であることを検査し、重複していたら非ゼロで終了する。
#
# なぜ必要か（TASK-399 の実測）:
# backlog CLI の採番は backlog/tasks（と drafts）だけを走査し、archive /
# completed 配下を見ない。このため「そのとき最大番号のタスクをアーカイブする」と
# その番号が空きに戻り、次の task create が同じ ID を再発行する。実際に
# TASK-389 が「行番号表示（取り下げ・アーカイブ）」と「スクロール位置のバグ」の
# 2 件に振られ、コード内コメントから ID を引くと誤った方に当たる状態になった。
# CLI 側に ID を指定する手段が無いため、リポジトリ側で落とす。
#
# 使い方: scripts/check-task-id-uniqueness.sh [--self-test]

ROOT="$(git rev-parse --show-toplevel)"

collect_ids() {
  # ファイル名ではなく frontmatter の id を見る（リネームだけでは直らないため）。
  find "$ROOT/backlog" -type f -name '*.md' -print0 |
    xargs -0 grep -H -m1 -E '^id: ' 2>/dev/null |
    sed -E 's/^(.*):id: (.*)$/\2\t\1/'
}

report_duplicates() {
  local ids="$1"
  local dups
  dups=$(printf '%s\n' "$ids" | cut -f1 | sort | uniq -d)
  [ -n "$dups" ] || return 0

  echo "重複しているタスク ID があります:" >&2
  while IFS= read -r id; do
    [ -n "$id" ] || continue
    echo "  $id" >&2
    printf '%s\n' "$ids" | awk -F'\t' -v id="$id" '$1 == id { print "    " $2 }' >&2
  done <<<"$dups"
  cat >&2 <<'MSG'

backlog CLI の採番は archive / completed を走査しないため、最大番号の
タスクをアーカイブすると同じ ID が再発行されます。どちらか一方に
未使用の新しい ID を振り直し、参照（コード内コメント・他タスク）も
追随させてください。
MSG
  return 1
}

if [ "${1:-}" = "--self-test" ]; then
  # 検知が働くこと自体を確認する。実リポジトリを汚さないよう一時ディレクトリで行う。
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  mkdir -p "$tmp/tasks" "$tmp/archive/tasks"
  printf 'id: TASK-1\n' > "$tmp/tasks/task-1 - a.md"
  printf 'id: TASK-1\n' > "$tmp/archive/tasks/task-1 - b.md"
  ids=$'TASK-1\t'"$tmp/tasks/task-1 - a.md"$'\nTASK-1\t'"$tmp/archive/tasks/task-1 - b.md"
  if report_duplicates "$ids" 2>/dev/null; then
    echo "self-test 失敗: 重複を検知できませんでした" >&2
    exit 1
  fi
  echo "self-test OK: 重複を検知しました"
  exit 0
fi

[ -d "$ROOT/backlog" ] || exit 0

all_ids="$(collect_ids)"
report_duplicates "$all_ids"
echo "タスク ID は一意です（$(printf '%s\n' "$all_ids" | grep -c . ) 件）。"
