#!/usr/bin/env bash
set -euo pipefail

# ステージされた JS/TS があれば Oxlint と Oxfmt を実行する（TASK-498）。
# CI（ci.yml の js-test / site.yml の test）と同じチェックをコミット時点で検知する
# ための pre-commit フック用スクリプト。
#
# **落とす側に倒してある。** 型グループの肥大化を見る warn-type-group-growth.sh は
# 警告のみに留めてあるが、あちらは「作業の途中段階では超えていて当然」という性質の
# 判定で、落とすと --no-verify の常用圧力になる。こちらは lint と整形で、どちらも
# その場で機械的に直せる（npm run lint:fix / npm run format）。直せるものを通すと、
# 直っていないコードが CI まで進んで往復が増える。

cd "$(git rev-parse --show-toplevel)"

staged=$(git diff --cached --name-only --diff-filter=ACM)

# node_modules を要求するので、依存が入っていない環境では黙って抜ける
# （クローン直後に npm ci をまだ回していない場合など）。検査が走らなかったことは
# CI 側で必ず捕まる。
run_for() {
  local dir="$1" pattern="$2"

  printf '%s\n' "$staged" | grep -qE "$pattern" || return 0
  if [ ! -x "$dir/node_modules/.bin/oxlint" ] || [ ! -x "$dir/node_modules/.bin/oxfmt" ]; then
    echo "スキップ: $dir の依存が未インストール（npm ci を実行すると検査されます）" >&2
    return 0
  fi
  # site は --type-aware で走るため tsgolint の実体も要る（TASK-505）。無いまま
  # 呼ぶと "Failed to find tsgolint executable" で落ち、依存不足だと分からない。
  if [ "$dir" = site ] && [ ! -x "$dir/node_modules/.bin/tsgolint" ]; then
    echo "スキップ: $dir の oxlint-tsgolint が未インストール（npm ci を実行すると検査されます）" >&2
    return 0
  fi

  # 対象はステージされたファイルだけでなくディレクトリ全体にする。1 ファイルの
  # 変更が別ファイルの指摘を生む（import を消して未使用になる等）ため、
  # ファイル単位で見ると CI と結果が食い違う。
  (cd "$dir" && npm run --silent lint && npm run --silent format:check)
}

run_for site '^site/.*\.(ts|tsx|js|mjs|cjs)$'
run_for BefoldApp '^BefoldApp/.*\.(ts|tsx|js|mjs|cjs)$'

# 共通方針を変えると両方の結果が変わるので、設定ファイル単独の変更でも両方回す。
if printf '%s\n' "$staged" | grep -qE '^\.ox(lint|fmt)rc\.json$'; then
  run_for site '.*'
  run_for BefoldApp '.*'
fi
