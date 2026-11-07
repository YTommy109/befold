#!/usr/bin/env bash
# 完了した git worktree を掃除する。
# 「完了」の判定は scripts/lib/branch-completion.sh を参照（worktree-reset.sh と共有）。
# 使い方: scripts/worktree-clean.sh [--force] [--no-fetch] [--keep-branch]
#   （引数なし）: dry-run。削除対象の表示のみ（既定・安全側）
#   --force     : 実際に worktree を削除する
#   --no-fetch  : 事前の git fetch --prune を省略する（オフライン時）
#   --keep-branch: worktree 削除後にローカルブランチを残す（既定は削除する）
#   --self-test : 削除対象の判定が働くことを一時リポジトリで確認する（CI 用）
# 未コミットの変更がある worktree は --force でも削除せずスキップする。
set -euo pipefail

err() { echo "エラー: $*" >&2; exit 1; }

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
    *) err "不明な引数: '$arg'（--force | --no-fetch | --keep-branch | --self-test）" ;;
  esac
done

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
# shellcheck source=lib/branch-completion.sh
. "$ROOT/scripts/lib/branch-completion.sh"

# 削除対象の判定が働くこと自体を確認する。スクリプトは自身の置かれたリポジトリを掃除するので、
# 一時リポジトリへ複製して実際に走らせる（gh だけ偽物に差し替える）。
run_self_test() {
  local tmp
  tmp="$(mktemp -d)"
  trap "rm -rf '$tmp'" EXIT
  export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
  mkdir "$tmp/bin" "$tmp/pr-heads"
  git init -q --bare -b main "$tmp/origin.git"
  git clone -q "$tmp/origin.git" "$tmp/main" 2>/dev/null
  mkdir -p "$tmp/main/scripts/lib"
  cp "$ROOT/scripts/worktree-clean.sh" "$tmp/main/scripts/"
  cp "$ROOT/scripts/lib/branch-completion.sh" "$tmp/main/scripts/lib/"
  (
    cd "$tmp/main"
    git switch -q -c main
    printf 'a\n' > f.txt && git add f.txt && git commit -q -m base
    git push -q origin main

    # squashed-done: squash merge 済み。その後に別の PR が同じ f.txt を変更する
    git worktree add -q -b squashed-done "$tmp/wt-done"
    (
      cd "$tmp/wt-done"
      printf 'a\nfeature\n' > f.txt && git commit -q -am feature
      git push -q -u origin squashed-done
      git rev-parse HEAD > "$tmp/pr-heads/squashed-done"
    )
    printf 'a\nfeature\n' > f.txt && git commit -q -am 'squash of squashed-done (#1)'
    printf 'a\nfeature\nlater\n' > f.txt && git commit -q -am 'later PR touching f.txt (#2)'

    # gone-unpushed: squash merge 後に、同じブランチへ未プッシュコミットを積む
    git worktree add -q -b gone-unpushed "$tmp/wt-unpushed"
    (
      cd "$tmp/wt-unpushed"
      printf 'g\n' > g.txt && git add g.txt && git commit -q -m pr
      git push -q -u origin gone-unpushed
      git rev-parse HEAD > "$tmp/pr-heads/gone-unpushed"
      printf 'h\n' > h.txt && git add h.txt && git commit -q -m unpushed
    )
    printf 'g\n' > g.txt && git add g.txt && git commit -q -m 'squash of gone-unpushed (#3)'

    # active: 上流が生きている作業中のブランチ
    git worktree add -q -b active "$tmp/wt-active"
    (
      cd "$tmp/wt-active"
      printf 'x\n' > x.txt && git add x.txt && git commit -q -m active
      git push -q -u origin active
    )

    git push -q origin main
    git push -q origin --delete squashed-done gone-unpushed
    git fetch -q --prune
  )
  # 偽 gh: --head <ブランチ> について pr-heads/<ブランチ> を「マージ済み PR の headRefOid」として返す
  cat > "$tmp/bin/gh" <<'EOF'
#!/bin/sh
while [ $# -gt 0 ]; do
  if [ "$1" = --head ]; then cat "$PR_HEADS_DIR/$2" 2>/dev/null; fi
  shift
done
exit 0
EOF
  chmod +x "$tmp/bin/gh"

  local fail=0 b track out
  report_failure() { echo "self-test 失敗: $*" >&2; fail=1; }
  run_clean() { PATH="$tmp/bin:$PATH" PR_HEADS_DIR="$tmp/pr-heads" bash "$tmp/main/scripts/worktree-clean.sh" "$@" 2>&1; }
  has_line() { printf '%s\n' "$1" | grep -qF -- "$2"; }

  # 前提: どちらも本当に [gone] である（崩れると、以下の検証が何も測らなくなる）
  for b in squashed-done gone-unpushed; do
    track="$(git -C "$tmp/main" for-each-ref --format='%(upstream:track)' "refs/heads/$b")"
    [ "$track" = "[gone]" ] || report_failure "前提の $b が [gone] ではありません: '$track'"
  done

  out="$(run_clean)"
  has_line "$out" '[squashed] squashed-done ' \
    || report_failure "squash 済みで後続 PR が同じファイルを変更したブランチが削除対象に入りません"
  has_line "$out" '] gone-unpushed ' \
    && report_failure "[gone] で未プッシュコミットを持つブランチが削除対象に入りました"
  has_line "$out" 'スキップ: gone-unpushed' \
    || report_failure "[gone] で削除対象から外したブランチの理由が表示されません"
  if has_line "$out" '] active ' || has_line "$out" 'スキップ: active'; then
    report_failure "上流が生きている作業中のブランチが出力に現れました"
  fi

  # gh を使わない --no-fetch では PR head を照合できないので、内容が違えば削除しない
  out="$(run_clean --no-fetch)"
  has_line "$out" '] squashed-done ' \
    && report_failure "--no-fetch で内容の異なるブランチが削除対象に入りました"

  # 実削除でも同じ結論になる
  run_clean --force >/dev/null
  git -C "$tmp/main" rev-parse --verify --quiet refs/heads/squashed-done >/dev/null \
    && report_failure "--force で squash 済みのブランチが削除されませんでした"
  git -C "$tmp/main" rev-parse --verify --quiet refs/heads/gone-unpushed >/dev/null \
    || report_failure "--force で未プッシュコミットを持つブランチが削除されました"

  [ "$fail" -eq 0 ] && echo "self-test OK: squash 済みは削除対象に入り、未プッシュコミットがあれば [gone] でも残る"
  return "$fail"
}
if $SELF_TEST; then run_self_test; exit; fi

cd "$ROOT"

# 誤って自分自身やメインリポジトリを消さないための基準パス
CURRENT_WT="$(git rev-parse --show-toplevel)"
MAIN_WT="$(git worktree list --porcelain | awk '/^worktree /{print $2; exit}')"

if $FETCH; then
  echo "リモートを取得中（--prune）..."
  git fetch --prune --quiet || echo "警告: fetch に失敗しました（オフライン?）。ローカル情報で続行します" >&2
fi

BASE="$(branch_completion_base)" \
  || err "基準のブランチが見つかりません（origin/main も main も無し）。"

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

      reason="$(branch_completion_reason "$branch" "$BASE" "$FETCH")"
      if [ -z "$reason" ]; then
        # [gone] は判定には使わない。PR は終わったように見えるのに残る理由を伝えるためだけに見る
        if [ "$(git for-each-ref --format='%(upstream:track)' "refs/heads/$branch" 2>/dev/null)" = "[gone]" ]; then
          echo "スキップ: $branch （上流は削除済みだが、$BASE に入っていない変更あり）" >&2
        fi
        continue
      fi

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
