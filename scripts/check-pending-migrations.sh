#!/usr/bin/env bash
set -euo pipefail

# D1 に未適用のマイグレーションが溜まっていないか見張る。1 件でもあれば
# 非ゼロで終了する。適用は一切しない（読み取りのみ）。
#
# 用途は staging の drift 検知。staging はマイグレーションもデプロイも
# 手動トリガーのため、実行を忘れるとスキーマだけ古い状態が誰にも気づかれずに
# 残る（実際に 20260730022424_add_as_org.sql が約 10 日間当たっていなかった）。
# 定期実行でジョブを失敗させ、GitHub の通知で気づけるようにする。
#
# 自動適用にしていないのは、スキーマだけ進んでコードが古い状態を CI 自身が
# 作り出しうるため。未適用に気づいたら Site Staging ワークフローを回し、
# マイグレーションとデプロイを同じ順序でまとめて反映する。
#
# 使い方: scripts/check-pending-migrations.sh [データベース名] [--env 名]
# 要求環境: site/ で wrangler が実行できること（CLOUDFLARE_API_TOKEN 等）

DB="${1:-befold-analytics}"
WRANGLER_ENV="${2:-}"
ROOT="$(git rev-parse --show-toplevel)"
# shellcheck source=lib/d1-pending-migrations.sh
. "$ROOT/scripts/lib/d1-pending-migrations.sh"
cd "$ROOT/site"

pending_list=$(d1_pending_migrations "$DB" "$WRANGLER_ENV")

if [ -z "$pending_list" ]; then
  echo "${DB}: 未適用のマイグレーションはありません。"
  exit 0
fi

count=$(printf '%s\n' "$pending_list" | wc -l | tr -d ' ')

cat >&2 <<MSG
${DB} に未適用のマイグレーションが ${count} 件あります。

$(printf '%s\n' "$pending_list" | sed 's/^/  - /')

Site Staging ワークフローを手動実行してください
（マイグレーション適用 → Worker デプロイの順で反映されます）。
MSG
exit 1
