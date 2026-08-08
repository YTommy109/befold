#!/usr/bin/env bash
# D1 に未適用のマイグレーションファイル名を列挙する共通処理。
#
# check-destructive-migrations.sh（未適用の中身を検査する）と
# check-pending-migrations.sh（未適用が溜まっていないか見張る）の両方が使う。
# 「何が未適用か」の判定を二重に実装すると、片方だけ直したときに
# 本番とチェックで見えているものがずれるため、ここに一本化する。
#
# source して d1_pending_migrations <データベース名> [wrangler の --env 名] を呼ぶ。
# 未適用のファイル名を 1 行 1 件で stdout に出す（0 件なら何も出さない）。
# 適用済み一覧の取得に失敗した場合は stderr に理由を出して 1 を返す。

# shellcheck shell=bash

d1_pending_migrations() {
  local db="$1"
  local wrangler_env="${2:-}"
  # macOS の bash 3.2 では set -u 下で空配列の "${a[@]}" が unbound になるため、
  # 展開側を ${a[@]+...} で守る。--env 未指定（本番）でも呼ばれる。
  local -a env_args=()
  [ -n "$wrangler_env" ] && env_args=(--env "$wrangler_env")

  # 適用済みマイグレーション名の一覧。d1_migrations は wrangler の既定の管理テーブル。
  # 認証切れや権限不足でも wrangler は JSON のエラーオブジェクトを stdout に出すため、
  # jq へ直接つながず一旦受け取って形を検証する。素通しにすると
  # "jq: Cannot index object with number" という原因の分からない失敗になる。
  local raw applied
  raw=$(
    npx wrangler d1 execute "$db" --remote ${env_args[@]+"${env_args[@]}"} --json \
      --command "SELECT name FROM d1_migrations" 2>&1
  ) || true

  if applied=$(printf '%s' "$raw" | jq -er '.[0].results[].name' 2>/dev/null); then
    : # 取得できた
  elif printf '%s' "$raw" | jq -e '.[0].results | length == 0' >/dev/null 2>&1; then
    # 管理テーブルはあるが 1 件も適用されていない。
    applied=''
  elif printf '%s' "$raw" | grep -qiE 'no such table: *d1_migrations'; then
    # まだ一度もマイグレーションを当てていないデータベース。全件が未適用。
    echo "d1_migrations が存在しません。全件を未適用として扱います。" >&2
    applied=''
  else
    cat >&2 <<MSG
適用済みマイグレーションの取得に失敗しました（データベース: ${db}）。

よくある原因:
  - CLOUDFLARE_API_TOKEN が未設定、失効、または権限不足
    （必要な権限: Account / D1 / Edit）
  - ローカル実行なら wrangler の認証切れ（npx wrangler login）

wrangler の出力:
MSG
    printf '%s\n' "$raw" | tail -20 >&2
    return 1
  fi

  local file name
  for file in migrations/*.sql; do
    [ -e "$file" ] || continue
    name=$(basename "$file")
    printf '%s\n' "$applied" | grep -qxF "$name" && continue
    printf '%s\n' "$name"
  done
}
