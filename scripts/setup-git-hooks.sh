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
install_hook pre-commit scripts/block-main-commits.sh scripts/swiftformat-lint.sh
# commit-msg は件名を見るチェックなので pre-commit ではなくここ(メッセージ確定後)。
install_hook commit-msg scripts/check-gate-commit-scope.sh
