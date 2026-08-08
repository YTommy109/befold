#!/usr/bin/env bash
set -euo pipefail

# 規約文書がバッククォートで名指しするコードシンボルが、実際に宣言として存在するかを検査する。
#
# 背景(TASK-374 / TASK-381): .claude/CLAUDE.md が模範例として引用していた
# `BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:)` は、同ブランチの先行コミットで
# 削除済みの関数だった。文書がコードを名指しする限り同型の陳腐化は再発するため機械化する。
#
# 検査対象は「Type.member」形式(先頭大文字の型 + ドット + メンバ)の引用に限定する。
# 単独の型名(`ViewerStore`)やコマンド(`swift build`)まで広げると、外部フレームワークの型・
# 一般語・シェル語が大量に誤検知になり、除外リストの維持コストのほうが大きくなるため。
# 引数ラベル付き(`Type.member(to:isEnabled:)`)はラベルの一致まで確認する。
#
# 使い方:
#   scripts/check-doc-symbols.sh              # 既定の規約文書を検査する
#   scripts/check-doc-symbols.sh docs/foo.md  # 任意の文書を検査する
#   scripts/check-doc-symbols.sh --self-test  # 検知が働くことを一時ファイルで確認する

ROOT="$(git rev-parse --show-toplevel)"
SOURCE_DIR="$ROOT/BefoldApp"
ALLOWLIST="$ROOT/scripts/doc-symbol-allowlist.txt"

# 既定の検査対象は「規約文書」= リポジトリ直下と .claude の CLAUDE.md。
DEFAULT_DOCS=("$ROOT/CLAUDE.md" "$ROOT/.claude/CLAUDE.md")

command -v rg > /dev/null 2>&1 || { echo "エラー: rg (ripgrep) が必要です" >&2; exit 1; }

is_allowlisted() {
  [ -f "$ALLOWLIST" ] || return 1
  grep -v '^[[:space:]]*#' "$ALLOWLIST" | grep -v '^[[:space:]]*$' | grep -q -x -F "$1"
}

type_exists() {
  rg -q --type swift -e "(class|struct|enum|protocol|actor|typealias|extension)[[:space:]]+$1\b" "$SOURCE_DIR"
}

# 関数宣言を(複数行にまたがる引数リストごと)取り出す。宣言が改行で折り返される例があるため
# -U で複数行にまたがって拾う(MainMenuBuilder.addDisplayModeItems が実際にこの形)。
func_decls() {
  # 折り返された宣言は複数行で返るため、1 宣言 1 行へ畳んでからラベルを見る。
  rg -U --no-filename --type swift -o -e "func[[:space:]]+$1\([^)]*\)" "$SOURCE_DIR" \
    | awk '/^func /{if (n++) printf "\n"; printf "%s", $0; next} {printf " %s", $0}
           END {if (n) printf "\n"}' || true
}

member_exists() {
  rg -q --type swift -e "(var|let|case|func)[[:space:]]+$1\b" "$SOURCE_DIR"
}

# `Type.member(a:b:)` のラベル列が、実在する宣言のいずれかと一致するかを見る。
labels_match() {
  local member="$1" labels="$2" decls
  decls="$(func_decls "$member")"
  [ -n "$decls" ] || return 1
  if [ -z "$labels" ]; then
    # `Type.member()` は引数なしの宣言を要求する。
    echo "$decls" | grep -q -E "func[[:space:]]+$member\([[:space:]]*\)"
    return
  fi
  local decl ok label
  while IFS= read -r decl; do
    [ -n "$decl" ] || continue
    ok=1
    for label in ${labels//:/ }; do
      # 宣言側は `to menu: NSMenu` や `isSourceDiffEnabled: Bool` の形。
      echo "$decl" | grep -q -E "[(,][[:space:]]*(_[[:space:]]+)?$label[[:space:]]*[:[:space:]]" || ok=0
    done
    [ "$ok" = 1 ] && return 0
  done <<< "$decls"
  return 1
}

FAILED=0

check_doc() {
  local doc="$1"
  [ -f "$doc" ] || { echo "エラー: 文書が見つかりません: $doc" >&2; FAILED=1; return; }

  local line_no span symbol type member labels reason
  # バッククォート引用を行番号付きで取り出す。
  while IFS= read -r line_no; do
    span="${line_no#*:}"
    line_no="${line_no%%:*}"
    symbol="${span//\`/}"
    # Type.member / Type.member(labels) だけを対象にする。
    [[ "$symbol" =~ ^[A-Z][A-Za-z0-9_]*\.[a-z][A-Za-z0-9_]*(\([A-Za-z0-9_:]*\))?$ ]] || continue
    # `FeatureGate.swift` のようなファイル名は同じ形をしているが、シンボル参照ではない。
    [[ "$symbol" =~ \.(swift|md|mmd|js|json|ya?ml|html|css|sh|xcstrings|plist|app)$ ]] && continue
    is_allowlisted "$symbol" && continue

    type="${symbol%%.*}"
    member="${symbol#*.}"
    labels=""
    if [[ "$member" == *"("* ]]; then
      labels="${member#*(}"
      labels="${labels%)}"
      member="${member%%(*}"
    fi

    reason=""
    if ! type_exists "$type"; then
      reason="型 $type の宣言が見つかりません"
    elif [[ "$symbol" == *"("* ]]; then
      labels_match "$member" "$labels" \
        || reason="$member の宣言(引数ラベル ${labels:-なし})が見つかりません"
    elif ! member_exists "$member"; then
      reason="メンバ $member の宣言が見つかりません"
    fi

    if [ -n "$reason" ]; then
      echo "${doc#"$ROOT"/}:$line_no: \`$symbol\` — $reason" >&2
      FAILED=1
    fi
  done < <(grep -n -o '`[^`]*`' "$doc")
}

self_test() {
  local tmp
  tmp="$(mktemp -t check-doc-symbols)"
  trap 'rm -f "$tmp"' RETURN
  cat > "$tmp" <<'EOF'
削除済みの例: `BookmarkShortcut.keyEquivalent(isSourceDiffEnabled:)`
実在する例: `ModeSegments.modes(isSourceDiffEnabled:)`
EOF
  local out
  out="$(FAILED=0; check_doc "$tmp" 2>&1 1>/dev/null || true)"
  if ! echo "$out" | grep -q 'BookmarkShortcut'; then
    echo "self-test 失敗: 削除済みシンボルを検知できませんでした" >&2
    return 1
  fi
  if echo "$out" | grep -q 'ModeSegments'; then
    echo "self-test 失敗: 実在するシンボルを誤検知しました" >&2
    echo "$out" >&2
    return 1
  fi
  echo "self-test OK: 削除済みシンボルを検知し、実在シンボルは通過しました"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "$#" -gt 0 ]; then
  DOCS=("$@")
else
  DOCS=("${DEFAULT_DOCS[@]}")
  # 既定の実行では毎回 self-test を通す。検知そのものが壊れた（抽出条件を絞りすぎた等）
  # 場合に、グリーンのまま何も見ていない状態になるのを防ぐ（0.1 秒未満）。
  self_test > /dev/null || { echo "check-doc-symbols.sh の self-test が失敗しました" >&2; exit 1; }
fi

for doc in "${DOCS[@]}"; do
  check_doc "$doc"
done

if [ "$FAILED" != 0 ]; then
  cat >&2 <<'EOF'

規約文書が実在しないシンボルを引用しています。
文書側の記述を現在のコードに合わせて更新するか、意図的な引用(例示のための架空名・
外部フレームワークの API)であれば scripts/doc-symbol-allowlist.txt に追記してください。
EOF
  exit 1
fi
