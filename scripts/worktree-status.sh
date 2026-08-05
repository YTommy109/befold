#!/usr/bin/env bash
# git worktree・ブランチ・PR・作業内容の対応を 1 コマンドで一覧する（読み取り専用）。
# 使い方: scripts/worktree-status.sh [--no-pr] [--fetch]
#   （引数なし）: 全 worktree の状態を表示する（gh があれば PR も引く）
#   --no-pr    : PR の照会を省略する（オフライン時・高速化）
#   --fetch    : 事前に git fetch --prune する（origin/main との差分を最新にする）
# ウィンドウを閉じた後に「どの worktree で何をしていたか」を会話なしで特定するためのもの。
# 何も変更しない。削除は scripts/worktree-clean.sh、ブランチ切り直しは
# scripts/worktree-reset.sh を使う。
set -euo pipefail

err() { echo "エラー: $*" >&2; exit 1; }

MAIN_BRANCH="main"
WITH_PR=true
FETCH=false
for arg in "$@"; do
  case "$arg" in
    --no-pr) WITH_PR=false ;;
    --fetch) FETCH=true ;;
    -h|--help)
      sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    *) err "不明な引数: '$arg'（--no-pr | --fetch）" ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || err "git リポジトリではありません"

if [ "$FETCH" = true ]; then
  git fetch --prune --quiet || echo "警告: fetch に失敗しました（オフライン？）" >&2
fi

if [ "$WITH_PR" = true ] && ! command -v gh >/dev/null 2>&1; then
  echo "注意: gh が無いため PR 列は '-' になります（--no-pr で抑止）" >&2
  WITH_PR=false
fi

CURRENT_WT="$(git rev-parse --show-toplevel)"

# git worktree list --porcelain を「パス<TAB>ブランチ」に畳む
git worktree list --porcelain | awk '
  /^worktree /  { path = substr($0, 10) }
  /^branch /    { br = substr($0, 8); sub(/^refs\/heads\//, "", br) }
  /^detached$/  { br = "(detached)" }
  /^$/          { if (path != "") { print path "\t" (br == "" ? "-" : br); path = ""; br = "" } }
  END           { if (path != "") print path "\t" (br == "" ? "-" : br) }
' | while IFS=$'\t' read -r wt branch; do
  [ -n "$wt" ] || continue

  mark=" "
  [ "$wt" = "$CURRENT_WT" ] && mark="*"

  # 作業内容: 最終コミットの日付と件名
  last="$(git -C "$wt" log -1 --format='%ad  %s' --date=format:'%m/%d %H:%M' 2>/dev/null || echo '-')"

  # 未コミット変更の有無
  if [ -n "$(git -C "$wt" status --porcelain 2>/dev/null)" ]; then
    dirty="未コミットあり"
  else
    dirty="clean"
  fi

  # origin/main との差分（このブランチ固有のコミット数）
  if git rev-parse --verify --quiet "origin/$MAIN_BRANCH" >/dev/null 2>&1; then
    ahead="$(git -C "$wt" rev-list --count "origin/$MAIN_BRANCH..HEAD" 2>/dev/null || echo '?')"
  else
    ahead="?"
  fi

  # PR（open / merged / closed を問わず最新の 1 件）
  pr="-"
  if [ "$WITH_PR" = true ] && [ "$branch" != "-" ] && [ "$branch" != "(detached)" ]; then
    pr="$(gh pr list --head "$branch" --state all --limit 1 \
            --json number,state --jq '.[] | "#\(.number) \(.state)"' 2>/dev/null || true)"
    [ -n "$pr" ] || pr="なし"
  fi

  printf '%s %s\n' "$mark" "$(basename "$wt")"
  printf '    ブランチ: %s  (origin/%s から %s commit)\n' "$branch" "$MAIN_BRANCH" "$ahead"
  printf '    PR      : %s\n' "$pr"
  printf '    作業状態: %s\n' "$dirty"
  printf '    最終作業: %s\n' "$last"
  printf '    パス    : %s\n\n' "$wt"
done

echo "* = 現在の worktree"
