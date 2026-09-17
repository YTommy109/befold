#!/usr/bin/env bash
# R2 (befold-dist) を正として、しきい値バージョン以前の dev リリースを
# 一括削除する（GitHub Release／タグ／R2 オブジェクト／appcast item の4箇所）。
#
# なぜ必要か（2026-09-17 の手動クリーンアップの実測）:
# GitHub Releases 一覧を対象の洗い出しに使うと、既に Release だけ個別に
# 消えて R2 にだけ残る orphan オブジェクトを取りこぼす
# （site/src/lib/dist.ts のとおり、配布の正は R2 側）。また
# GitHub Release／タグ／R2 オブジェクトを消しても appcast.xml /
# appcast-develop.xml の item は自動連動せず、壊れたダウンロードリンクが
# 残る。この4箇所を同一タグ単位でまとめて処理することで、手動作業で
# 実際に起きた取りこぼしを構造的に防ぐ。
#
# 使い方:
#   scripts/cleanup-old-dev-releases.sh [--dry-run] <しきい値バージョン>
#   例: scripts/cleanup-old-dev-releases.sh 1.19.0
#     → ベースバージョン（-dev の前の X.Y.Z）が 1.19.0 以下の dev タグを
#       すべて削除する。stable リリースと、しきい値より新しい dev は対象外。
#
# 要求環境:
#   - gh コマンドで GitHub 認証済みであること
#   - R2 管理用の Cloudflare API トークン（権限: Account / R2 Storage / Edit）を
#     CLOUDFLARE_R2_ADMIN_TOKEN 環境変数、または Keychain
#     （service: befold-r2-admin）で渡すこと。作り方は site/README.md
#     「古い dev リリースの一括削除」節を参照
#   - jq / python3 がインストールされていること
set -euo pipefail

err() {
  echo "エラー: $*" >&2
  exit 1
}

BUCKET="befold-dist"
ACCOUNT_ID="${CLOUDFLARE_ACCOUNT_ID:-96b3602a71be49f99732550f9f3dedad}"
API="https://api.cloudflare.com/client/v4/accounts/${ACCOUNT_ID}/r2/buckets/${BUCKET}"

command -v jq >/dev/null || err "jq が必要です"
command -v gh >/dev/null || err "gh が必要です"
command -v python3 >/dev/null || err "python3 が必要です"

DRY_RUN=false
if [ "${1:-}" = "--dry-run" ]; then
  DRY_RUN=true
  shift
fi

THRESHOLD="${1:-}"
[ -n "$THRESHOLD" ] || err "使い方: scripts/cleanup-old-dev-releases.sh [--dry-run] <しきい値バージョン (例: 1.19.0)>"
echo "$THRESHOLD" | grep -qE '^[0-9]+\.[0-9]+\.[0-9]+$' \
  || err "しきい値バージョンは X.Y.Z の形で指定してください（指定値: ${THRESHOLD}）"

token="${CLOUDFLARE_R2_ADMIN_TOKEN:-}"
if [ -z "$token" ]; then
  token="$(security find-generic-password -s befold-r2-admin -w 2>/dev/null || true)"
fi
if [ -z "$token" ]; then
  cat >&2 <<'MSG'
R2 管理用トークンが見つかりません。Cloudflare ダッシュボード
（My Profile → API Tokens → Create Token）で "Workers R2 Storage: Edit"
権限のスコープドトークンを作成し、次のいずれかで渡してください。
作り方の詳細は site/README.md「古い dev リリースの一括削除」節を参照。

  security add-generic-password -a "$USER" -s befold-r2-admin -w
  # あるいは
  export CLOUDFLARE_R2_ADMIN_TOKEN=...
MSG
  exit 1
fi

api_get() {
  curl -sS -H "Authorization: Bearer ${token}" "${API}$1"
}

# --- 1. R2 を正として対象タグを列挙する ---
echo "R2 (${BUCKET}) から dev タグを列挙しています..." >&2
prefixes="$(api_get "/objects?prefix=releases/&delimiter=/&per_page=1000" \
  | jq -r '.result_info.delimited[]?')"

targets=()
while IFS= read -r p; do
  [ -n "$p" ] || continue
  tag="${p#releases/}"
  tag="${tag%/}"
  case "$tag" in
    v*-dev.*)
      base="$(echo "$tag" | sed -E 's/^v([0-9]+\.[0-9]+\.[0-9]+)-dev\.[0-9]+$/\1/')"
      lowest="$(printf '%s\n%s\n' "$base" "$THRESHOLD" | sort -V | head -1)"
      [ "$lowest" = "$base" ] && targets+=("$tag")
      ;;
  esac
done <<<"$prefixes"

if [ "${#targets[@]}" -eq 0 ]; then
  echo "対象なし（しきい値 ${THRESHOLD} 以前の dev タグは R2 に存在しません）"
  exit 0
fi

echo "対象: ${#targets[@]} 件"
printf '  %s\n' "${targets[@]}"

if $DRY_RUN; then
  echo "(--dry-run のためここで終了します)"
  exit 0
fi

# --- 2. GitHub Release / タグを削除する（存在しなければスキップ） ---
for tag in "${targets[@]}"; do
  if gh release view "$tag" >/dev/null 2>&1; then
    gh release delete "$tag" --cleanup-tag -y
    echo "GitHub: ${tag} を削除しました"
  else
    echo "GitHub: ${tag} の Release は既に存在しません（スキップ）"
  fi
done

# --- 3. R2 オブジェクトを削除する（delete-by-list で一括） ---
all_keys=()
for tag in "${targets[@]}"; do
  keys="$(api_get "/objects?prefix=releases/${tag}/&per_page=1000" | jq -r '.result[]?.key')"
  while IFS= read -r k; do
    [ -n "$k" ] && all_keys+=("$k")
  done <<<"$keys"
done

if [ "${#all_keys[@]}" -gt 0 ]; then
  body="$(printf '%s\n' "${all_keys[@]}" | jq -R . | jq -s .)"
  curl -sS -X DELETE -H "Authorization: Bearer ${token}" -H "Content-Type: application/json" \
    -d "$body" "${API}/objects" | jq -r '.result[]? | "R2: " + .key + " を削除しました"'
fi

# --- 4. appcast から該当 item を除去する ---
target_versions="$(printf '%s\n' "${targets[@]}" | sed 's/^v//')"
for key in appcast.xml appcast-develop.xml; do
  tmp="$(mktemp)"
  if ! curl -sS -f -H "Authorization: Bearer ${token}" "${API}/objects/${key}" -o "$tmp"; then
    rm -f "$tmp"
    continue
  fi
  out="$(mktemp)"
  removed="$(TARGET_VERSIONS="$target_versions" python3 - "$tmp" "$out" <<'PYEOF'
import os
import sys
import xml.etree.ElementTree as ET

src, dst = sys.argv[1], sys.argv[2]
targets = set(os.environ["TARGET_VERSIONS"].splitlines())

ns = {"sparkle": "http://www.andymatuschak.org/xml-namespaces/sparkle"}
ET.register_namespace("sparkle", ns["sparkle"])
tree = ET.parse(src)
channel = tree.getroot().find("channel")
removed = 0
for item in list(channel.findall("item")):
    ver = item.findtext("sparkle:shortVersionString", namespaces=ns)
    if ver in targets:
        channel.remove(item)
        removed += 1
tree.write(dst, encoding="utf-8", xml_declaration=True)
print(removed)
PYEOF
  )"
  if [ "$removed" -gt 0 ]; then
    curl -sS -X PUT -H "Authorization: Bearer ${token}" -H "Content-Type: application/xml" \
      --data-binary @"$out" "${API}/objects/${key}" >/dev/null
    echo "appcast: ${key} から ${removed} 件の item を削除しました"
  fi
  rm -f "$tmp" "$out"
done

echo "完了しました。"
