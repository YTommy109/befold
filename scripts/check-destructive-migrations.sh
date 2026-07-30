#!/usr/bin/env bash
set -euo pipefail

# 本番 D1 に未適用のマイグレーションを走査し、破壊的な文が含まれていたら
# 非ゼロで終了する。CI のデプロイジョブから呼び出し、取り返しのつかない
# 適用を自動実行させないための歯止め。
#
# 検査対象を「未適用のものだけ」に絞るのが要点。全ファイルを見ると、
# 破壊的変更を一度手動適用した後も永久に落ち続けてしまう。適用済みに
# なればこのスクリプトは自然に通るようになる。
#
# 使い方: scripts/check-destructive-migrations.sh [データベース名]
# 要求環境: site/ で wrangler が実行できること（CLOUDFLARE_API_TOKEN 等）

DB="${1:-befold-analytics}"
cd "$(git rev-parse --show-toplevel)/site"

# 適用済みマイグレーション名の一覧。d1_migrations は wrangler の既定の管理テーブル。
# 認証切れや権限不足でも wrangler は JSON のエラーオブジェクトを stdout に出すため、
# jq へ直接つながず一旦受け取って形を検証する。素通しにすると
# "jq: Cannot index object with number" という原因の分からない失敗になる。
raw=$(
  npx wrangler d1 execute "$DB" --remote --json \
    --command "SELECT name FROM d1_migrations" 2>&1
) || true

if applied=$(printf '%s' "$raw" | jq -er '.[0].results[].name' 2>/dev/null); then
  : # 取得できた
elif printf '%s' "$raw" | jq -e '.[0].results | length == 0' >/dev/null 2>&1; then
  # 管理テーブルはあるが 1 件も適用されていない。
  applied=''
elif printf '%s' "$raw" | grep -qiE 'no such table: *d1_migrations'; then
  # まだ一度もマイグレーションを当てていないデータベース。全件が未適用。
  echo "d1_migrations が存在しません。全件を未適用として扱います。"
  applied=''
else
  cat >&2 <<MSG
適用済みマイグレーションの取得に失敗しました（データベース: ${DB}）。

よくある原因:
  - CLOUDFLARE_API_TOKEN が未設定、失効、または権限不足
    （必要な権限: Account / D1 / Edit）
  - ローカル実行なら wrangler の認証切れ（npx wrangler login）

wrangler の出力:
MSG
  printf '%s\n' "$raw" | tail -20 >&2
  exit 1
fi

# SQLite の破壊的な操作。Atlas はカラム型変更などをテーブル再構築
# (新テーブル作成 → コピー → DROP → RENAME) として出力するため、
# DROP と RENAME を見れば型変更も捕捉できる。
DESTRUCTIVE='DROP[[:space:]]+(TABLE|COLUMN|INDEX)|RENAME[[:space:]]+(TO|COLUMN)|DELETE[[:space:]]+FROM|TRUNCATE'

pending=0
found=0

for file in migrations/*.sql; do
  [ -e "$file" ] || continue
  name=$(basename "$file")

  if printf '%s\n' "$applied" | grep -qxF "$name"; then
    continue
  fi

  pending=$((pending + 1))
  echo "未適用: $name"

  # コメント行を除いてから判定する（説明文の DROP で誤検知しないため）。
  if hits=$(grep -vE '^[[:space:]]*--' "$file" | grep -inE "$DESTRUCTIVE"); then
    found=1
    echo "  ⚠️ 破壊的な文を検出:"
    printf '%s\n' "$hits" | sed 's/^/    /'
  fi
done

if [ "$pending" -eq 0 ]; then
  echo "未適用のマイグレーションはありません。"
  exit 0
fi

if [ "$found" -eq 1 ]; then
  cat >&2 <<'MSG'

破壊的なマイグレーションが未適用のため、自動適用を中止しました。
内容を確認し、必要なら手動で適用してから再実行してください。

  cd site && npm run migrate:remote
MSG
  exit 1
fi

echo "破壊的な文は含まれていません。自動適用を続行できます。"
