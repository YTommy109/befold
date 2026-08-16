#!/usr/bin/env bash
set -euo pipefail

# クローン直後に一度だけ実行する git hooks のセットアップ。
# worktree は .git/hooks を共有するため、メインリポジトリで一度実行すれば
# 以降作成する worktree にも自動的に反映される。
# post-commit（dagayn の graph 更新）は dagayn 自身がインストールするため対象外。

HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"

install_hook() {
  local name="$1"
  shift
  {
    echo '#!/usr/bin/env bash'
    # set -e がないと途中のスクリプトが失敗しても後続が実行され、
    # フック全体の終了コードが最後のスクリプトのものに上書きされてしまう。
    echo 'set -e'
    echo 'ROOT="$(git rev-parse --show-toplevel)"'
    for script in "$@"; do
      # フックの引数をそのまま渡す(commit-msg は $1 のメッセージファイルが必須)。
      # 引数を取らない pre-commit / post-checkout では空に展開されるだけ。
      echo "\"\$ROOT/$script\" \"\$@\""
    done
  } > "$HOOKS_DIR/$name"
  chmod +x "$HOOKS_DIR/$name"
  echo "installed: $name -> $*"
}

install_hook post-checkout scripts/worktree-init.sh
# block-main-commits.sh を先に実行し、main への直接コミットは他のチェックより
# 前に弾く(無駄な処理をさせない)。swiftformat-lint.sh は CI の build-and-test
# ジョブと同じ SwiftFormat チェックをコミット時点で検知する。
# check-doc-symbols.sh は規約文書が名指しするシンボルの実在を見る（CI は BefoldApp/** の
# 変更でしか走らないため、文書とコードの両方に触れうるコミット時点で検知する）。
# check-task-id-uniqueness.sh は backlog の ID 重複を見る（CLI の採番が archive /
# completed を走査しないため、最大番号のタスクをアーカイブすると同じ ID が再発行される）。
# check-analytics-query-guard.sh は解析用 D1 の読み取り専用ガードが実効であることを
# 見る（判定を緩めると拒否すべき SQL を通した時点で落ちる）。
# oxc-lint.sh は JS/TS の Oxlint と Oxfmt を見る（CI と同じチェック。lint も整形も
# その場で機械的に直せるので、警告ではなく落とす側にしてある）。
# warn-type-group-growth.sh は型グループ（Foo.swift + Foo+*.swift の合算）の肥大化を見る。
# これだけは終了コードで落とさない（警告のみ）。作業の途中段階でコミットが止まると
# --no-verify を常用する圧力になり、フック全体が形骸化するため。ブロックは CI で行う。
install_hook pre-commit scripts/block-main-commits.sh scripts/swiftformat-lint.sh \
  scripts/oxc-lint.sh scripts/check-doc-symbols.sh scripts/check-task-id-uniqueness.sh \
  scripts/check-analytics-query-guard.sh scripts/warn-type-group-growth.sh
