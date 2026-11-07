# ブランチの作業がすべて main に入っているかの判定。worktree-reset.sh と worktree-clean.sh が
# source する。どちらもこの判定の結果でブランチを削除するので、判定はここだけに置く。

# 判定の基準にする ref を出力する。origin/main を優先し、無ければローカル main を使う。
# どちらも無ければ何も出力せず 1 を返す。
branch_completion_base() {
  local main_branch=main
  if git rev-parse --verify --quiet "refs/remotes/origin/$main_branch" >/dev/null; then
    echo "origin/$main_branch"
  elif git rev-parse --verify --quiet "refs/heads/$main_branch" >/dev/null; then
    echo "$main_branch"
  else
    return 1
  fi
}

# GitHub 上でマージ済みの PR の head が、ブランチの先端と同じ SHA か。
# 同じなら PR に含まれない作業は無い。後続の PR が同じファイルを変更していても
# 影響されない（内容の照合は、その場合に未マージと誤判定する）。
# squash 後に未プッシュコミットを積んでいれば先端が PR head とずれるので一致しない。
# gh が無い・取得失敗は「一致しない」側へ倒す。stdin を閉じるのは、呼び出し元の
# while read ループの入力を gh に読ませないため。
branch_completion_pr_merged_at_tip() {
  command -v gh >/dev/null 2>&1 || return 1
  local tip heads
  tip="$(git rev-parse "$1")"
  heads="$(gh pr list --head "$1" --state merged --json headRefOid -q '.[].headRefOid' </dev/null 2>/dev/null || true)"
  printf '%s\n' "$heads" | grep -qx "$tip"
}

# 完了の理由を出力する。merged か squashed で、未完了なら何も出力しない。常に 0 を返す。
# 使い方: branch_completion_reason <ブランチ> <基準の ref> <gh を使うか: true|false>
#
# 上流の追跡状態（[gone]）は判定に使わない。squash merge された PR の後、同じ
# ローカルブランチへ**さらに別の未プッシュコミットを積む**ことがあり、その場合も
# 上流はとっくに削除済みのまま [gone] を示し続けるため、安全の根拠にならない
# （実例: TASK-528 の実装 2 コミットを squash-merge 済みブランチへ追記したまま
# [gone] 判定で切り直され、reflog からの復旧を要した）。中身を見て判定する。
branch_completion_reason() {
  local branch="$1" base="$2" use_gh="$3"

  if git merge-base --is-ancestor "$branch" "$base" 2>/dev/null; then
    echo merged
    return 0
  fi
  if [ "$use_gh" = true ] && branch_completion_pr_merged_at_tip "$branch"; then
    echo squashed
    return 0
  fi

  local merge_base
  merge_base="$(git merge-base "$branch" "$base" 2>/dev/null || true)"
  [ -n "$merge_base" ] || return 0

  # -z + read -d '' でファイル名の空白・非 ASCII 文字を壊さず配列へ集める
  # （bash 3.2 は mapfile/readarray を持たないため手書きループにする。macOS 既定の
  # /bin/bash が 3.2 のままなことは把握しておくこと）。
  local touched=() file
  while IFS= read -r -d '' file; do
    touched+=("$file")
  done < <(git diff -z --name-only "$merge_base" "$branch")
  if [ ${#touched[@]} -eq 0 ]; then
    echo merged
    return 0
  fi

  # --name-only の出力はルート基準で、pathspec は cwd 基準で解釈される。ルートで照合しないと、
  # サブディレクトリからの実行で pathspec がどのファイルにも一致せず、差分なしと誤判定する。
  # 実ファイル名を glob として解釈させないよう literal にする。
  local top
  top="$(git rev-parse --show-toplevel)"
  if git -C "$top" --literal-pathspecs diff --quiet "$base" "$branch" -- "${touched[@]}"; then
    echo squashed
  fi
  return 0
}
