#!/usr/bin/env bash
# テストが過去に残した UserDefaults の plist を掃除する。
# BefoldTestSupport の makeIsolatedDefaults はかつて "<接頭辞>-<UUID>" の永続
# スイートを作っており、~/Library/Preferences に plist が溜まり続けていた。
# 現在はメモリ上の UserDefaults を返すため新たに増えることはないが、
# それ以前に堆積したぶんはこのスクリプトで掃除する（一度実行すれば足りる）。
# 使い方: scripts/clean-test-defaults.sh [--force]
#   （引数なし）: dry-run。対象の件数と接頭辞ごとの内訳の表示のみ（既定・安全側）
#   --force     : 実際に削除する
# 対象は「<接頭辞><区切り><正準形式の UUID>.plist」に一致するファイルのみ。
# 区切りが "-" の場合は接頭辞を問わない。"." の場合は接頭辞にドットを含まないものに限定し、
# 逆 DNS 形式(com.example.App)の実在アプリドメインを巻き込まない（旧 ephemeralDefaults は
# "<接頭辞>.<UUID>" のドット区切りで永続スイートを作っていたため対象に含める）。
set -euo pipefail

PREFS_DIR="$HOME/Library/Preferences"
# 8-4-4-4-12 の 16 進。BSD find の -regex は basic regex のため \{n\} を使う。
UUID_RE='[0-9A-Fa-f]\{8\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{4\}-[0-9A-Fa-f]\{12\}'

FORCE=false
for arg in "$@"; do
  case "$arg" in
    --force) FORCE=true ;;
    -h|--help)
      sed -n '2,10p' "$0" | sed 's/^# \{0,1\}//'
      exit 0
      ;;
    *) echo "エラー: 不明な引数: $arg" >&2; exit 1 ;;
  esac
done

[ -d "$PREFS_DIR" ] || { echo "$PREFS_DIR がありません"; exit 0; }

# 対象は数万件になりうるため、走査は 1 回だけ行って一覧を使い回す。
LIST=$(mktemp -t befold-test-defaults)
trap 'rm -f "$LIST"' EXIT
# ハイフン区切り(旧 makeIsolatedDefaults)と、接頭辞にドットを含まないドット区切り
# (旧 ephemeralDefaults の "<接頭辞>.<UUID>")の両方を対象にする。後者は接頭辞を
# `[^./]*`(ドットなし)に限定することで、`com.openai.chat.Foo.<UUID>.plist` のような
# 逆 DNS 形式の実在アプリドメインを巻き込まない。
find "$PREFS_DIR" -maxdepth 1 -type f \
  \( -regex ".*-${UUID_RE}\.plist" -o -regex ".*/[^./]*\.${UUID_RE}\.plist" \) \
  > "$LIST" 2>/dev/null || true

count=$(wc -l < "$LIST" | tr -d ' ')

if [ "$count" -eq 0 ]; then
  echo "掃除対象の plist はありません。"
  exit 0
fi

echo "対象: ${count} 個"
echo "内訳（接頭辞ごとの上位 10 件）:"
sed -E "s|.*/||; s/[-.][0-9A-Fa-f]{8}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{4}-[0-9A-Fa-f]{12}\.plist$//" "$LIST" \
  | sort | uniq -c | sort -rn | head -10 \
  | sed 's/^/  /'

if [ "$FORCE" = false ]; then
  echo
  echo "dry-run です。実際に削除するには --force を付けて再実行してください。"
  exit 0
fi

echo
echo "削除しています..."
tr '\n' '\0' < "$LIST" | xargs -0 rm -f
echo "削除しました: ${count} 個"

# cfprefsd が削除済みドメインをキャッシュしたままだと再作成されうるため、
# 掃除後は再起動させておく（macOS が自動で立ち上げ直す）。
if pkill -x cfprefsd 2>/dev/null; then
  echo "cfprefsd を再起動しました。"
fi
