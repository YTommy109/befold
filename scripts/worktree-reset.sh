#!/usr/bin/env bash
# worktree を消さずに、現在のブランチを origin/main 起点で切り直す。
# PR がマージされ上流ブランチが削除された後、同じ worktree で次のタスクを始めるために使う。
# 使い方: scripts/worktree-reset.sh [新ブランチ名] [--force] [--no-fetch] [--keep-branch]
#   新ブランチ名  : 省略時はランダムな 2 語（例: juniper-flint）を自動生成する
#   --force       : 旧ブランチが未マージでも切り直す（旧ブランチのコミットは失われる）
#   --no-fetch    : 事前の git fetch --prune を省略する（オフライン時）
#   --keep-branch : 旧ローカルブランチを削除せず残す（既定は削除する）
# 未コミットの変更がある場合は --force でも中断する。
set -euo pipefail

err() { echo "エラー: $*" >&2; exit 1; }

MAIN_BRANCH="main"

NEW_BRANCH=""
FORCE=false
FETCH=true
KEEP_BRANCH=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --no-fetch) FETCH=false ;;
    --keep-branch) KEEP_BRANCH=true ;;
    -h|--help)
      sed -n '2,9p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) err "不明な引数: '$arg'（--force | --no-fetch | --keep-branch）" ;;
    *)
      [ -n "$NEW_BRANCH" ] && err "新ブランチ名が複数指定されています: '$NEW_BRANCH' と '$arg'"
      NEW_BRANCH="$arg" ;;
  esac
done

git rev-parse --git-dir >/dev/null 2>&1 || err "git リポジトリ内で実行してください。"

# メインリポジトリでの実行を拒否する（main を巻き込んで切り替えないため）
CURRENT_WT="$(git rev-parse --show-toplevel)"
MAIN_WT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"
[ "$CURRENT_WT" = "$MAIN_WT" ] && err "メインリポジトリでは実行できません（worktree 内で実行してください）。"

OLD_BRANCH="$(git symbolic-ref --quiet --short HEAD)" \
  || err "detached HEAD です。ブランチをチェックアウトしてから実行してください。"

# 未コミットの変更は --force でも保護する
if [ -n "$(git status --porcelain)" ]; then
  err "未コミットの変更があります。コミットまたは退避してから実行してください。"
fi

if $FETCH; then
  echo "リモートを取得中（--prune）..."
  git fetch --prune --quiet || echo "警告: fetch に失敗しました（オフライン?）。ローカル情報で続行します" >&2
fi

# 起点は origin/main を優先し、無ければローカル main にフォールバックする
if git rev-parse --verify --quiet "refs/remotes/origin/$MAIN_BRANCH" >/dev/null; then
  BASE="origin/$MAIN_BRANCH"
elif git rev-parse --verify --quiet "refs/heads/$MAIN_BRANCH" >/dev/null; then
  BASE="$MAIN_BRANCH"
else
  err "起点ブランチが見つかりません（origin/$MAIN_BRANCH も $MAIN_BRANCH も無し）。"
fi

# 完了判定: BASE に取り込み済み（squash merge では成立しない）か、上流が [gone]
REASON=""
if git merge-base --is-ancestor "$OLD_BRANCH" "$BASE" 2>/dev/null; then
  REASON="merged"
elif [ "$(git for-each-ref --format='%(upstream:track)' "refs/heads/$OLD_BRANCH" 2>/dev/null)" = "[gone]" ]; then
  REASON="gone"
fi

if [ -z "$REASON" ]; then
  if ! $FORCE; then
    echo "エラー: ブランチ $OLD_BRANCH は未マージです" >&2
    echo "  （$BASE 未取り込み / 上流も生存中）" >&2
    echo "  作業を捨ててよければ --force を付けてください" >&2
    exit 1
  fi
  REASON="forced"
fi

# 新ブランチ名: 未指定ならランダムな 2 語を生成し、既存ブランチと衝突しないものを選ぶ
branch_exists() { git rev-parse --verify --quiet "refs/heads/$1" >/dev/null; }

if [ -n "$NEW_BRANCH" ]; then
  git check-ref-format "refs/heads/$NEW_BRANCH" || err "ブランチ名として使えません: '$NEW_BRANCH'"
  [ "$NEW_BRANCH" = "$OLD_BRANCH" ] && err "現在のブランチと同じ名前です: '$NEW_BRANCH'"
  branch_exists "$NEW_BRANCH" && err "ブランチが既に存在します: '$NEW_BRANCH'"
else
  HEADS=(arroyo mesa caldera sierra butte canyon playa dune ridge basin bluff wash notch mirador cinder falcon)
  TAILS=(creosote zephyr saltbush juniper flint agave ocotillo yucca cactus lightning quartz sage thistle ember tumbleweed dry)
  for _ in $(seq 1 50); do
    candidate="${HEADS[$((RANDOM % ${#HEADS[@]}))]}-${TAILS[$((RANDOM % ${#TAILS[@]}))]}"
    if [ "$candidate" != "$OLD_BRANCH" ] && ! branch_exists "$candidate"; then
      NEW_BRANCH="$candidate"
      break
    fi
  done
  [ -z "$NEW_BRANCH" ] && err "ブランチ名の自動生成に失敗しました。名前を明示して再実行してください。"
fi

echo ""
echo "旧ブランチ: $OLD_BRANCH ($REASON)"
git switch --quiet -c "$NEW_BRANCH" "$BASE"
echo "新ブランチ: $NEW_BRANCH ← $BASE ($(git rev-parse --short HEAD))"

if $KEEP_BRANCH; then
  echo "保持: 旧ブランチ $OLD_BRANCH"
else
  git branch -D "$OLD_BRANCH" >/dev/null 2>&1 \
    && echo "削除: 旧ブランチ $OLD_BRANCH" \
    || echo "警告: 旧ブランチ $OLD_BRANCH を削除できませんでした" >&2
fi
