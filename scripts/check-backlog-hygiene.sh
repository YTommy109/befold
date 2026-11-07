#!/usr/bin/env bash
set -euo pipefail

# backlog 運用ルールのうち、機械的に判定できるものを検査する。
# backlog-hygiene-reviewer の起動を「意味の判定が要るときだけ」に絞るための前段。
#
# 違反（終了コード 1）: ルールから機械的に確定するもの
#   - backlog/ 配下の未コミットの変更（取り残し）
#   - ブランチで追加・更新したタスクに priority が無い
# 要判定（終了コード 0）: 機械的には確定せず、backlog-hygiene-reviewer に渡すもの
#   - 既存タスクの ordinal が変わっている（--ordinal で順序を表そうとしていないか）
#   - feat / fix のコミットにタスクや Issue との対応が見当たらない
#
# 見ないもの: タスクや Issue がある feat / fix を Issue と backlog のどちらで管理すべきか。
# コミットの分け方（--amend でまとめるべきか、1 コミット内の無関係な混入）。どちらも意味の
# 判定なので、agent を明示的に呼んだときに見る。未 push の件数で要判定にすると、複数コミットの
# ブランチを初めて push するたびに agent が起動する（実測 約 4.2 万トークン）一方、PR は
# squash マージなので分け方の実害は小さい。
#
# 使い方: scripts/check-backlog-hygiene.sh [--base <rev>] [--self-test]
# 終了コード: 0 = 違反なし / 1 = 違反あり / 2 = 実行できない

BASE="origin/main"
SCRIPT="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

run_checks() {
  local merge_base violations="" needs="" violation_count=0 needs_count=0
  merge_base="$(git merge-base "$BASE" HEAD 2> /dev/null)" || {
    echo "エラー: $BASE と HEAD の共通の祖先が見つかりません" >&2
    return 2
  }

  add_violation() {
    violations+="  $1"$'\n'
    violation_count=$((violation_count + 1))
  }
  add_needs() {
    needs+="  $1"$'\n'
    needs_count=$((needs_count + 1))
  }

  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    add_violation "未コミットの backlog 変更: $line"
  done < <(git -c core.quotepath=off status --porcelain -- backlog/)

  # ファイル名に空白が入るため、タブ区切りの行をそのまま読む。
  local status path
  while IFS=$'\t' read -r status path; do
    [ -n "$path" ] || continue
    if ! git show "HEAD:$path" | awk 'NR == 1 { next } /^---$/ { exit } /^priority:[[:space:]]*[^[:space:]]/ { found = 1 } END { exit !found }'; then
      add_violation "priority が無いタスク: $path"
    fi
    if [ "$status" = "M" ] && git diff "$merge_base" HEAD -- "$path" | grep -qE '^[-+]ordinal:'; then
      add_needs "ordinal が変わったタスク: $path"
    fi
  done < <(git -c core.quotepath=off diff --name-status --no-renames --diff-filter=AM "$merge_base" HEAD -- backlog/tasks/)

  local sha subject message
  while IFS= read -r sha; do
    [ -n "$sha" ] || continue
    subject="$(git log -1 --format=%s "$sha")"
    printf '%s\n' "$subject" | grep -qE '^(feat|fix)(\([^)]*\))?!?:' || continue
    message="$(git log -1 --format=%B "$sha")"
    printf '%s\n' "$message" | grep -qE 'TASK-[0-9]+|#[0-9]+' && continue
    [ -z "$(git diff-tree --no-commit-id --name-only -r "$sha" -- backlog/)" ] || continue
    add_needs "対応するタスクや Issue が見当たらない: $(git log -1 --format=%h "$sha") $subject"
  done < <(git rev-list --no-merges "$merge_base..HEAD")

  if [ "$violation_count" -gt 0 ]; then
    printf '== 違反 ==\n%s' "$violations"
  fi
  if [ "$needs_count" -gt 0 ]; then
    printf '== 要判定（backlog-hygiene-reviewer に渡す） ==\n%s' "$needs"
  fi
  echo "結果: 違反 $violation_count 件 / 要判定 $needs_count 件"
  [ "$violation_count" -eq 0 ]
}

self_test() {
  local repo fail=0
  repo="$(mktemp -d)"
  # shellcheck disable=SC2064 # repo は今の値で固定する
  trap "rm -rf '$repo'" RETURN

  tg() {
    git -C "$repo" -c user.name=test -c user.email=test@example.com \
      -c commit.gpgsign=false -c core.hooksPath=/dev/null "$@"
  }
  # 期待する「終了コード / 違反件数 / 要判定件数」を、実際の実行結果と比べる。
  expect() {
    local name="$1" want_code="$2" want_summary="結果: 違反 $3 件 / 要判定 $4 件" out code=0
    out="$(cd "$repo" && "$SCRIPT" --base main 2>&1)" || code=$?
    if [ "$code" != "$want_code" ] || ! printf '%s\n' "$out" | grep -qxF "$want_summary"; then
      echo "self-test 失敗: $name (終了コード $code)" >&2
      printf '%s\n' "$out" >&2
      fail=1
    fi
  }
  start_branch() {
    tg reset -q --hard
    tg clean -qfd
    tg checkout -q main
    tg checkout -q -B work
  }
  task_file() {
    printf -- '---\nid: %s\n%sordinal: %s\n---\n\nbody\n' "$1" "$2" "$3"
  }

  tg init -q -b main
  mkdir -p "$repo/backlog/tasks"
  task_file TASK-1 $'priority: low\n' 1000 > "$repo/backlog/tasks/task-1 - a.md"
  tg add -A
  tg commit -q -m 'chore: 初期状態'

  start_branch
  tg commit -q --allow-empty -m 'chore: 内部の変更'
  expect '問題のないコミット' 0 0 0

  start_branch
  echo more >> "$repo/backlog/tasks/task-1 - a.md"
  expect '未コミットの backlog 変更' 1 1 0

  start_branch
  task_file TASK-2 '' 2000 > "$repo/backlog/tasks/task-2 - b.md"
  tg add -A
  tg commit -q -m 'chore: 起票する'
  expect 'priority が無いタスク' 1 1 0

  start_branch
  task_file TASK-2 $'priority: high\n' 2000 > "$repo/backlog/tasks/task-2 - b.md"
  tg add -A
  tg commit -q -m 'chore: 起票する'
  expect '新規タスクの ordinal は要判定にしない' 0 0 0

  start_branch
  task_file TASK-1 $'priority: low\n' 9000 > "$repo/backlog/tasks/task-1 - a.md"
  tg add -A
  tg commit -q -m 'chore: 順序を変える'
  expect '既存タスクの ordinal の変更' 0 0 1

  start_branch
  tg commit -q --allow-empty -m 'fix: 不具合を直す'
  expect '対応の無い fix' 0 0 1

  start_branch
  tg commit -q --allow-empty -m 'fix: 不具合を直す' -m 'TASK-1 の対応'
  expect '本文にタスク ID がある fix' 0 0 0

  start_branch
  tg commit -q --allow-empty -m 'fix(viewer)!: 不具合を直す (#12)'
  expect '件名に Issue 番号がある fix' 0 0 0

  start_branch
  tg commit -q --allow-empty -m 'chore: 1 件目'
  tg commit -q --allow-empty -m 'chore: 2 件目'
  expect '複数コミットだけでは要判定にしない' 0 0 0

  [ "$fail" = 0 ] || return 1
  echo "self-test OK"
}

while [ "$#" -gt 0 ]; do
  case "$1" in
    --base)
      [ "$#" -ge 2 ] || { echo "エラー: --base には値が必要です" >&2; exit 2; }
      BASE="$2"
      shift 2
      ;;
    --self-test)
      self_test
      exit $?
      ;;
    *)
      echo "使い方: scripts/check-backlog-hygiene.sh [--base <rev>] [--self-test]" >&2
      exit 2
      ;;
  esac
done

cd "$(git rev-parse --show-toplevel)"
run_checks
