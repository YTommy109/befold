#!/usr/bin/env bash
# 手動ベンダリングされた同梱 JS/CSS ライブラリの実バージョンを 1 箇所で抽出する。
#
# 棚卸し手順（.claude/commands/check-vendored-deps.md /
# .claude/agents/vendored-deps-auditor.md）はこのスクリプトを呼ぶ。抽出コマンドを
# 文書側に散らすと、ファイルが移動・改名されたときに head や grep が黙って空振りし、
# 「監査したが何も出なかった」と「監査手順が壊れている」が区別できなくなるため
# （実績: TASK-433。6 件中 5 件のパスが壊れたまま気付かれずに残った）。
#
# 出力: "<name>\t<vendored>\t<recorded>" のタブ区切り。
#   vendored = 同梱ファイルから抽出した実バージョン
#   recorded = package.json / THIRD_PARTY_LICENSES.md の記録値
# いずれかが抽出できない、または両者が食い違う場合は非ゼロで終了する。
set -uo pipefail

cd "$(git rev-parse --show-toplevel)" || exit 1

RES="BefoldApp/BefoldKit/Resources"
PKG="BefoldApp/package.json"
LIC="$RES/THIRD_PARTY_LICENSES.md"

status=0

fail() {
  printf 'ERROR: %s\n' "$1" >&2
  status=1
}

# ファイルから 1 つ目のバージョン文字列を取り出す。
# $1=表示名 $2=ファイル $3=grep -o の正規表現(BRE)
extract() {
  local name=$1 file=$2 pattern=$3
  if [[ ! -f $file ]]; then
    fail "$name: 同梱ファイルが見つからない: $file"
    return 1
  fi
  local hit
  hit=$(grep -o "$pattern" "$file" | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
  if [[ -z $hit ]]; then
    fail "$name: $file から版を抽出できない（パターン: $pattern）"
    return 1
  fi
  printf '%s' "$hit"
}

# package.json の devDependencies から記録値を取り出す。
recorded_pkg() {
  local key=$1 hit
  hit=$(grep -o "\"$key\": \"[0-9.^~]*\"" "$PKG" | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
  printf '%s' "$hit"
}

# THIRD_PARTY_LICENSES.md の表から記録値を取り出す。
recorded_lic() {
  local component=$1 hit
  hit=$(grep -o "^| $component | [0-9.]* |" "$LIC" | head -1 | grep -o '[0-9]\+\.[0-9]\+\.[0-9]\+')
  printf '%s' "$hit"
}

# $1=表示名 $2=同梱版 $3=記録値 $4=記録元の説明
report() {
  local name=$1 vendored=$2 recorded=$3 source=$4
  if [[ -z $vendored ]]; then
    return
  fi
  if [[ -z $recorded ]]; then
    fail "$name: $source に版の記録が無い"
    recorded="-"
  elif [[ $vendored != "$recorded" ]]; then
    fail "$name: 同梱版 $vendored と $source の記録 $recorded が食い違う"
  fi
  printf '%s\t%s\t%s\n' "$name" "$vendored" "$recorded"
}

# markdown-it / github-markdown-css / DOMPurify は先頭バナーに版がある。
# highlight.js はバナーが無いため versionString リテラルを見る。
# mermaid は esbuild バンドルでバナーが無く、内部の version:"x.y.z" だけが手掛かり。
report "markdown-it" \
  "$(extract markdown-it "$RES/markdown-it.min.js" 'markdown-it [0-9.]*')" \
  "$(recorded_pkg markdown-it)" "package.json"
report "github-markdown-css" \
  "$(extract github-markdown-css "$RES/github-markdown.css" 'github-markdown-css v[0-9.]*')" \
  "$(recorded_pkg github-markdown-css)" "package.json"
report "dompurify" \
  "$(extract dompurify "$RES/dompurify.min.js" 'DOMPurify [0-9.]*')" \
  "$(recorded_pkg dompurify)" "package.json"
report "highlight.js" \
  "$(extract highlight.js "$RES/highlight.min.js" 'versionString="[0-9.]*"')" \
  "$(recorded_pkg highlight.js)" "package.json"
report "mermaid" \
  "$(extract mermaid "$RES/mermaid.min.js" 'version:"[0-9]\+\.[0-9]\+\.[0-9]\+"')" \
  "$(recorded_lic Mermaid)" "THIRD_PARTY_LICENSES.md"

# hljs テーマ CSS（github.css / github-dark.css）は highlight.js 本体に同梱される
# 配布物で、ファイル自身に版番号を持たない。版は highlight.js に従う。
for theme in github.css github-dark.css; do
  if [[ ! -f $RES/$theme ]]; then
    fail "hljs テーマ $theme が見つからない: $RES/$theme"
  fi
done

exit $status
