#!/usr/bin/env bash
# worktree を消さずに、現在のブランチを origin/main 起点で切り直す。
# PR がマージされ上流ブランチが削除された後、同じ worktree で次のタスクを始めるために使う。
# 使い方: scripts/worktree-reset.sh [新ブランチ名] [--force] [--no-fetch] [--keep-branch]
#   新ブランチ名  : 省略時はランダムな 2 語（例: juniper-flint）を自動生成する
#   --force       : 旧ブランチが未マージでも切り直す（旧ブランチのコミットは失われる）
#   --no-fetch    : 事前の git fetch --prune を省略する（オフライン時）
#   --keep-branch : 旧ローカルブランチを削除せず残す（既定は削除する）
#   --self-test   : 完了判定が働くことを一時リポジトリで確認する（CI 用）
# 未コミットの変更がある場合は --force でも中断する。
set -euo pipefail

err() { echo "エラー: $*" >&2; exit 1; }

# shellcheck source=lib/branch-completion.sh
. "$(cd "$(dirname "$0")" && pwd)/lib/branch-completion.sh"

NEW_BRANCH=""
FORCE=false
FETCH=true
KEEP_BRANCH=false
SELF_TEST=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    --no-fetch) FETCH=false ;;
    --keep-branch) KEEP_BRANCH=true ;;
    --self-test) SELF_TEST=true ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0 ;;
    -*) err "不明な引数: '$arg'（--force | --no-fetch | --keep-branch | --self-test）" ;;
    *)
      [ -n "$NEW_BRANCH" ] && err "新ブランチ名が複数指定されています: '$NEW_BRANCH' と '$arg'"
      NEW_BRANCH="$arg" ;;
  esac
done

# 完了判定が働くこと自体を確認する。一時の bare origin と linked worktree で、実際に
# このスクリプトを走らせる（gh だけ偽物に差し替える）。
run_self_test() {
  local tmp self
  tmp="$(mktemp -d)"
  self="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"
  trap "rm -rf '$tmp'" EXIT
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/main" 2>/dev/null
  (
    cd "$tmp/main"
    git switch -q -c main
    mkdir sub && printf 's\n' > sub/s.txt
    printf 'a\n' > f.txt && git add f.txt sub && git commit -q -m base
    git push -q origin main
    git worktree add -q -b feature "$tmp/wt"
    # feature: f.txt を変えたコミットを 1 つ積む
    cd "$tmp/wt" && printf 'a\nfeature\n' > f.txt && git commit -q -am feature
    # main: feature を squash merge し、その後に別の PR が同じ f.txt を変更する
    cd "$tmp/main"
    printf 'a\nfeature\n' > f.txt && git commit -q -am 'squash of feature (#1)'
    printf 'a\nfeature\nlater\n' > f.txt && git commit -q -am 'later PR touching f.txt (#2)'
    git push -q origin main
  )
  mkdir "$tmp/bin"
  # 偽 gh: 環境変数 FAKE_PR_HEAD を「マージ済み PR の headRefOid」として返す
  printf '#!/bin/sh\n[ -n "$FAKE_PR_HEAD" ] && echo "$FAKE_PR_HEAD"\nexit 0\n' > "$tmp/bin/gh"
  chmod +x "$tmp/bin/gh"

  local tip out fail=0
  tip="$(git -C "$tmp/wt" rev-parse HEAD)"
  # (a) 先端が PR head と一致 → 後続 PR が同じファイルを変えていても --force なしで切り直せる
  if ! out="$(cd "$tmp/wt" && PATH="$tmp/bin:$PATH" FAKE_PR_HEAD="$tip" bash "$self" next-a 2>&1)"; then
    echo "self-test 失敗: squash 済み（先端が PR head と一致）なのに切り直せませんでした" >&2
    printf '%s\n' "$out" >&2
    fail=1
  fi
  # (b) 先端が PR head と一致しない（squash 後に未プッシュコミットを積んだ）→ 従来どおり中断する
  git -C "$tmp/wt" switch -q -c feature "$tip"
  printf 'a\nfeature\nunpushed\n' > "$tmp/wt/f.txt" && git -C "$tmp/wt" commit -q -am unpushed
  if (cd "$tmp/wt" && PATH="$tmp/bin:$PATH" FAKE_PR_HEAD="$tip" bash "$self" next-b >/dev/null 2>&1); then
    echo "self-test 失敗: 未プッシュコミットを持つブランチを --force なしで切り直してしまいました" >&2
    fail=1
  fi
  # (c) (b) と同じ状態をサブディレクトリから実行しても中断する（内容の照合がルート基準であること）
  if (cd "$tmp/wt/sub" && PATH="$tmp/bin:$PATH" FAKE_PR_HEAD="$tip" bash "$self" next-c >/dev/null 2>&1); then
    echo "self-test 失敗: サブディレクトリからの実行で未プッシュコミットを持つブランチを切り直してしまいました" >&2
    fail=1
  fi
  [ "$fail" -eq 0 ] && echo "self-test OK: squash 済みは切り直せ、未プッシュコミットがあれば実行場所によらず中断する"
  return "$fail"
}
if $SELF_TEST; then run_self_test; exit; fi

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
BASE="$(branch_completion_base)" \
  || err "起点ブランチが見つかりません（origin/main も main も無し）。"

REASON="$(branch_completion_reason "$OLD_BRANCH" "$BASE" "$FETCH")"

if [ -z "$REASON" ]; then
  if ! $FORCE; then
    echo "エラー: ブランチ $OLD_BRANCH は未マージです" >&2
    echo "  （$BASE に取り込まれていない変更が残っています）" >&2
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
