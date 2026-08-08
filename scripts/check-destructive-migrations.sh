#!/usr/bin/env bash
set -euo pipefail

# D1 に未適用のマイグレーションを走査し、破壊的な文が含まれていたら
# 非ゼロで終了する。CI のデプロイジョブから呼び出し、取り返しのつかない
# 適用を自動実行させないための歯止め。
#
# 検査対象を「未適用のものだけ」に絞るのが要点。全ファイルを見ると、
# 破壊的変更を一度手動適用した後も永久に落ち続けてしまう。適用済みに
# なればこのスクリプトは自然に通るようになる。
#
# 使い方: scripts/check-destructive-migrations.sh [データベース名] [--env 名]
# 要求環境: site/ で wrangler が実行できること（CLOUDFLARE_API_TOKEN 等）

DB="${1:-befold-analytics}"
WRANGLER_ENV="${2:-}"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/d1-pending-migrations.sh
. "$ROOT/scripts/lib/d1-pending-migrations.sh"
cd "$ROOT/site"

# SQLite の破壊的な操作。Atlas はカラム型変更などをテーブル再構築
# (新テーブル作成 → コピー → DROP → RENAME) として出力するため、
# DROP と RENAME を見れば型変更も捕捉できる。
DESTRUCTIVE='DROP[[:space:]]+(TABLE|COLUMN|INDEX)|RENAME[[:space:]]+(TO|COLUMN)|DELETE[[:space:]]+FROM|TRUNCATE'

pending=0
found=0

# 一旦変数へ受ける。プロセス置換で読むと d1_pending_migrations の失敗
# （認証切れなど）が while の終了ステータスに現れず、未適用ゼロと
# 区別できないまま素通りしてしまう。
pending_list=$(d1_pending_migrations "$DB" "$WRANGLER_ENV")

while IFS= read -r name; do
  [ -n "$name" ] || continue
  pending=$((pending + 1))
  echo "未適用: $name"

  # コメント行を除いてから判定する（説明文の DROP で誤検知しないため）。
  if hits=$(grep -vE '^[[:space:]]*--' "migrations/$name" | grep -inE "$DESTRUCTIVE"); then
    found=1
    echo "  ⚠️ 破壊的な文を検出:"
    printf '%s\n' "$hits" | sed 's/^/    /'
  fi
done <<<"$pending_list"

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
