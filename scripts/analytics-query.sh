#!/usr/bin/env bash
set -euo pipefail

# 本番／staging の解析用 D1 を「読み取りだけ」で叩くための唯一の入口。
#
# なぜ必要か（TASK-395）:
# 解析データを実データで確認する経路として wrangler の d1 execute --remote が
# 使えるが、手元の wrangler 認証（OAuth）は d1 (write) を含むため、同じ経路で
# 本番 events テーブルへの UPDATE / DELETE / DROP も通ってしまう。events は
# 追記のみでバックアップ運用が無く、一度の事故で計測データを全損する。
# 「読み取りしかしない」を運用者の自制ではなく仕組みで担保する。
#
# 担保は 2 段構えで、どちらか一方が破れても書き込みには到達しない。
#   1. 認証: Account / D1 / Read だけを持つ API トークンを必須にする
#      （CLOUDFLARE_D1_READONLY_TOKEN）。Cloudflare 側で書き込みが弾かれる。
#   2. 文面: 渡された SQL が単一の読み取り文であることを検査する。
# さらに .claude/settings.json の PreToolUse フックが、このラッパを経由しない
# `d1 execute` の実行そのものを落とす。
#
# 使い方:
#   scripts/analytics-query.sh "SELECT ..."
#   scripts/analytics-query.sh --env staging "SELECT ..."
#   scripts/analytics-query.sh --self-test
#
# トークンの作り方は site/README.md「本番の解析データを読む」を参照。

ROOT="$(git rev-parse --show-toplevel)"

# 読み取り専用として許可する SQL の形。単一文であること・先頭が SELECT か
# WITH であること・末尾以外にセミコロンが無いことを見る。ATTACH / PRAGMA は
# SELECT で始まらないのでここで落ちる。
assert_read_only() {
  local sql="$1"
  local trimmed
  trimmed="$(printf '%s' "$sql" | sed -E 's/^[[:space:]]+//; s/[[:space:]]+$//; s/;[[:space:]]*$//')"

  if [ -z "$trimmed" ]; then
    echo "SQL が空です。" >&2
    return 1
  fi
  if printf '%s' "$trimmed" | grep -q ';'; then
    echo "複数文は実行できません（セミコロンで区切られています）: $sql" >&2
    return 1
  fi
  if ! printf '%s' "$trimmed" | grep -qiE '^(select|with)[[:space:](]'; then
    echo "読み取り専用の経路です。SELECT / WITH で始まる単一の文だけを実行できます: $sql" >&2
    return 1
  fi
  # WITH ... INSERT/UPDATE/DELETE ... のような書き込みを伴う CTE を弾く。
  if printf '%s' "$trimmed" | grep -qiE '(^|[[:space:](])(insert|update|delete|drop|alter|create|replace|attach|detach|vacuum|pragma|begin|commit|reindex)([[:space:](]|$)'; then
    echo "書き込み・スキーマ操作を含む文は実行できません: $sql" >&2
    return 1
  fi
  return 0
}

if [ "${1:-}" = "--self-test" ]; then
  # 検知が働くこと自体を確認する（実 D1 には接続しない）。
  fail=0
  allow=(
    "SELECT COUNT(*) FROM events"
    "  select kind, count(*) from events group by kind;  "
    "WITH d AS (SELECT * FROM events) SELECT COUNT(*) FROM d"
  )
  deny=(
    "DELETE FROM events"
    "UPDATE events SET kind = 'x'"
    "DROP TABLE events"
    "SELECT 1; DELETE FROM events"
    "PRAGMA table_list"
    "ATTACH DATABASE 'x' AS y"
    "WITH d AS (DELETE FROM events RETURNING *) SELECT * FROM d"
    ""
  )
  for sql in "${allow[@]}"; do
    if ! assert_read_only "$sql" 2>/dev/null; then
      echo "self-test 失敗: 通すべき SQL を弾きました: $sql" >&2
      fail=1
    fi
  done
  for sql in "${deny[@]}"; do
    if assert_read_only "$sql" 2>/dev/null; then
      echo "self-test 失敗: 弾くべき SQL を通しました: $sql" >&2
      fail=1
    fi
  done
  [ "$fail" -eq 0 ] || exit 1
  echo "self-test OK: 読み取り専用の判定は許可 ${#allow[@]} 件・拒否 ${#deny[@]} 件とも期待どおりです。"
  exit 0
fi

env_name="production"
if [ "${1:-}" = "--env" ]; then
  env_name="${2:-}"
  shift 2 || true
fi

case "$env_name" in
  production) database="befold-analytics" ;;
  staging) database="befold-analytics-staging" ;;
  *)
    echo "--env は production か staging を指定してください（指定値: ${env_name}）" >&2
    exit 1
    ;;
esac

sql="${1:-}"
if [ -z "$sql" ]; then
  cat >&2 <<'MSG'
使い方: scripts/analytics-query.sh [--env production|staging] "SELECT ..."
        scripts/analytics-query.sh --self-test
MSG
  exit 1
fi

assert_read_only "$sql"

token="${CLOUDFLARE_D1_READONLY_TOKEN:-}"
# 環境変数が無ければ Keychain から取る。トークンをシェル履歴やコマンドラインに
# 出さずに済む（エージェントとの対話ログにも残らない）。
if [ -z "$token" ]; then
  token="$(security find-generic-password -s befold-d1-readonly -w 2>/dev/null || true)"
fi

if [ -z "$token" ]; then
  cat >&2 <<'MSG'
読み取り専用トークンが見つかりません。

手元の wrangler 認証（OAuth）は d1 (write) を含むため、このスクリプトは
それを流用しません。Account / D1 / Read だけを持つ API トークンを作成し、
次のどちらかで渡してください。作成手順は site/README.md の
「本番の解析データを読む」節にあります。

  # 推奨: Keychain に入れる（履歴にもログにも残らない。-w を省くと対話入力）
  security add-generic-password -a "$USER" -s befold-d1-readonly -w

  # あるいは環境変数
  export CLOUDFLARE_D1_READONLY_TOKEN=...
MSG
  exit 1
fi

# 既定のアカウント（Tokutomi@degino.com's Account）。API トークン利用時は
# wrangler が OAuth のようにアカウントを推定できないため明示する。
account_id="${CLOUDFLARE_ACCOUNT_ID:-96b3602a71be49f99732550f9f3dedad}"

(
  cd "$ROOT/site"
  CLOUDFLARE_API_TOKEN="$token" \
  CLOUDFLARE_ACCOUNT_ID="$account_id" \
    npx wrangler d1 execute "$database" --remote --json --command "$sql"
)
