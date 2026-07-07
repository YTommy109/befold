#!/usr/bin/env bash
set -euo pipefail

# クローン直後に一度だけ実行する git hooks のセットアップ。
# worktree は .git/hooks を共有するため、メインリポジトリで一度実行すれば
# 以降作成する worktree にも自動的に反映される。
# post-commit（dagayn の graph 更新）は dagayn 自身がインストールするため対象外。

HOOKS_DIR="$(git rev-parse --git-common-dir)/hooks"

install_hook() {
  local name="$1"
  local script="$2"
  cat > "$HOOKS_DIR/$name" <<EOF
#!/usr/bin/env bash
ROOT="\$(git rev-parse --show-toplevel)"
"\$ROOT/$script"
EOF
  chmod +x "$HOOKS_DIR/$name"
  echo "installed: $name -> $script"
}

install_hook post-checkout scripts/worktree-init.sh
install_hook pre-commit scripts/cache-bust-docs.sh
