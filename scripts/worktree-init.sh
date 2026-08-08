#!/usr/bin/env bash
# worktree 作成時にメインリポジトリのファイル・ディレクトリへシンボリックリンクを張る。
# post-checkout フックから呼び出す。
export PATH="$HOME/.nix-profile/bin:$HOME/.local/bin:/opt/homebrew/bin:/usr/local/bin:$PATH"

GIT_DIR=$(git rev-parse --git-dir)
COMMON_DIR=$(git rev-parse --git-common-dir)

# worktree でない場合は何もしない
if [ "$GIT_DIR" = "$COMMON_DIR" ]; then
  exit 0
fi

ROOT="$(dirname "$COMMON_DIR")"

# メインリポジトリ側の実体を worktree から参照する。いずれも git 管理外で、
# worktree ごとに作り直すと内容がずれる or 作り忘れる類のもの。
#
# - .claude          : セッション設定
# - site/.dev.vars   : wrangler のローカル開発用シークレット。無いと
#                      /dashboard が 503 を返す（site/README.md 参照）。
#                      site/.dev.vars.example は git 追跡下なのでリンク不要。
for name in .claude site/.dev.vars; do
  SOURCE="$ROOT/$name"
  TARGET="$(pwd)/$name"
  # メイン側に実体が無いものは張らない（壊れたリンクを残すと原因が分かりにくい）
  [ -e "$SOURCE" ] || continue
  # 置き先の親ディレクトリが無い場合も張らない
  [ -d "$(dirname "$TARGET")" ] || continue
  if [ ! -e "$TARGET" ]; then
    ln -sfn "$SOURCE" "$TARGET"
  fi
done

dagayn build --skip-flows
