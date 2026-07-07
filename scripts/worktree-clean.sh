#!/usr/bin/env bash
# 完了した git worktree を掃除する。
# 「完了」= main にマージ済み、または上流ブランチが削除済み（PR マージ後の [gone]）。
# 使い方: scripts/worktree-clean.sh [--force] [--no-fetch] [--keep-branch]
#   （引数なし）: dry-run。削除対象の表示のみ（既定・安全側）
#   --force     : 実際に worktree を削除する
#   --no-fetch  : 事前の git fetch --prune を省略する（オフライン時）
#   --keep-branch: worktree 削除後にローカルブランチを残す（既定は削除する）
# 未コミットの変更がある worktree は --force でも削除せずスキップする。
set -euo pipefail

err() { echo "エラー: $*" >&2; exit 1; }

MAIN_BRANCH="main"

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
    *) err "不明な引数: '$arg'（--force | --no-fetch | --keep-branch）" ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

# 誤って自分自身やメインリポジトリを消さないための基準パス
CURRENT_WT="$(git rev-parse --show-toplevel)"
MAIN_WT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"

if $FETCH; then
  echo "リモートを取得中（--prune）..."
  git fetch --prune --quiet || echo "警告: fetch に失敗しました（オフライン?）。ローカル情報で続行します" >&2
fi

# worktree list をパースして (パス, ブランチ) を集める
declare -a CAND_PATHS=() CAND_BRANCHES=() CAND_REASONS=()
path=""
while IFS= read -r line; do
  case "$line" in
    "worktree "*) path="${line#worktree }"; branch="" ;;
    "branch refs/heads/"*)
      branch="${line#branch refs/heads/}"

      # メイン・現在・detached はスキップ
      [ "$path" = "$MAIN_WT" ] && continue
      [ "$path" = "$CURRENT_WT" ] && continue

      # 完了判定: main にマージ済み or 上流が [gone]
      reason=""
      if git merge-base --is-ancestor "$branch" "$MAIN_BRANCH" 2>/dev/null; then
        reason="merged"
      elif [ "$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)" = "[gone]" ]; then
        reason="gone"
      fi
      [ -z "$reason" ] && continue

      # 未コミット変更（追跡ファイルの変更・無視されない未追跡）があれば保護
      if [ -n "$(git -C "$path" status --porcelain 2>/dev/null)" ]; then
        echo "スキップ: $branch （未コミットの変更あり）" >&2
        continue
      fi

      CAND_PATHS+=("$path")
      CAND_BRANCHES+=("$branch")
      CAND_REASONS+=("$reason")
      ;;
  esac
done < <(git worktree list --porcelain)

if [ "${#CAND_PATHS[@]}" -eq 0 ]; then
  echo "掃除対象の worktree はありません。"
  exit 0
fi

echo ""
echo "完了した worktree（削除対象）:"
for i in "${!CAND_PATHS[@]}"; do
  printf '  [%s] %s  (%s)\n' "${CAND_REASONS[$i]}" "${CAND_BRANCHES[$i]}" "${CAND_PATHS[$i]}"
done
echo ""

if ! $FORCE; then
  echo "(dry-run) 実際に削除するには --force を付けて再実行してください。"
  exit 0
fi

for i in "${!CAND_PATHS[@]}"; do
  p="${CAND_PATHS[$i]}"
  b="${CAND_BRANCHES[$i]}"
  git worktree remove "$p" && echo "削除: worktree $p"
  if ! $KEEP_BRANCH; then
    git branch -D "$b" >/dev/null 2>&1 && echo "削除: ブランチ $b" || true
  fi
done

git worktree prune
echo ""
echo "掃除完了（${#CAND_PATHS[@]} 件）。"
