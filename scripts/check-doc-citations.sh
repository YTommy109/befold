#!/usr/bin/env bash
set -euo pipefail

# 現在仕様を語る文書(docs/adr/**, docs/dev/**)がコードを引用するときの形を検査する。
#
# 背景(TASK-550): docs/adr/0007 が `DOWNLOAD_URL`(`site/src/views/shared.tsx:13`)と
# 書いていたが、定数名も行番号も実態と違っていた(現在は DOWNLOAD_PATH、位置も別)。
# 行番号はコードを 1 行足すだけで無音でずれ、読み手(人にも AI にも)へ誤った前提を配る。
#
# 検査する規約は 2 つ。
#   1. 行番号引用(`path:12` / `path:12,34` / `path:12-20`)を禁止する。
#      位置を示したいならシンボル名を書く。名前の変更は grep で見つかるが、行の移動は
#      何も残さずにずれる。
#   2. 引用したパスが実在することを確認する。パス区切りを含む引用は ROOT / BefoldApp /
#      site からの相対で解決し、ファイル名だけの引用は同名ファイルが 1 つでもあるかを見る。
#
# シンボル名そのものの実在は検査しない。ADR は「採らなかった案」「存在しないもの」
# (`preBuildScripts` は無い、`allowFileAccessFromFileURLs` 相当の緩和が要る 等)を
# 論じる文書であり、実測では ADR 内の識別子 79 件中 9 件が「実在しない」と出て、
# うち 8 件はそう書くのが正しい記述だった(偽陽性 89%)。除外リストが本体になる。
#
# 使い方:
#   scripts/check-doc-citations.sh              # docs/adr/**.md と docs/dev/**.md を検査する
#   scripts/check-doc-citations.sh docs/foo.md  # 任意の文書を検査する
#   scripts/check-doc-citations.sh --self-test  # 検知が働くことを一時ファイルで確認する

ROOT="$(git rev-parse --show-toplevel)"

command -v rg > /dev/null 2>&1 || { echo "エラー: rg (ripgrep) が必要です" >&2; exit 1; }

# 引用と見なす拡張子。文中の一般語(`foo.bar`)を拾わないよう列挙で絞る。
CODE_EXT='swift|tsx?|jsx?|mjs|md|mmd|html|css|ya?ml|sh|json|plist|xcstrings'

FAILED=0

ALLOWLIST="$ROOT/scripts/doc-citation-allowlist.txt"

# 除外は「文書パス|引用」の組で書く。`viewer.js` のような名前をリポジトリ全体で
# 素通しにすると、別の文書で同じ名前が陳腐化したときに検知できなくなるため。
is_allowlisted() {
  [ -f "$ALLOWLIST" ] || return 1
  grep -q -x -F "${1#"$ROOT"/}|$2" "$ALLOWLIST"
}

FILES=""

# リポジトリ内の全ファイルを ROOT からの相対パスで 1 回だけ列挙する。
load_files() {
  [ -n "$FILES" ] && return 0
  FILES="$(rg --files --hidden "$ROOT" --glob '!**/.git/**' --glob '!**/.build/**' \
    --glob '!**/node_modules/**' 2>/dev/null | sed "s#^$ROOT/##" | sort -u)"
}

path_exists() {
  local p="$1" dir="$2"
  # 文書からの相対、または ROOT からの相対で直接解決できるならそれで済ませる。
  { [ -e "$dir/$p" ] || [ -e "$ROOT/$p" ]; } && return 0
  load_files
  # 途中のディレクトリを省いた引用（`viewer.html` / `__tests__/support/foo.js`）は、
  # パス末尾の一致で解決する。pipefail 下で grep -q が早期終了すると sed が SIGPIPE で
  # 落ちるため、パイプの右端に -q を置かない。
  grep -q -E "(^|/)$(sed 's/[.[\\*^$()+?{|]/\\&/g' <<< "$p")\$" <<< "$FILES"
}

check_doc() {
  local doc="$1"
  [ -f "$doc" ] || { echo "エラー: 文書が見つかりません: $doc" >&2; FAILED=1; return; }

  local line_no span citation path dir
  dir="$(dirname "$doc")"
  while IFS= read -r line_no; do
    span="${line_no#*:}"
    line_no="${line_no%%:*}"
    citation="${span//\`/}"
    # 拡張子で終わる、または拡張子のあとに行番号が続く引用だけを対象にする。
    [[ "$citation" =~ ^[A-Za-z0-9_./@-]+\.($CODE_EXT)(:[0-9]+([,-][0-9]+)*)*$ ]] || continue

    if [[ "$citation" == *:* ]]; then
      echo "${doc#"$ROOT"/}:$line_no: \`$citation\` — 行番号引用は使えません（位置はシンボル名で示してください）" >&2
      FAILED=1
      continue
    fi
    path="$citation"
    is_allowlisted "$doc" "$path" && continue
    if ! path_exists "$path" "$dir"; then
      echo "${doc#"$ROOT"/}:$line_no: \`$path\` — 引用されたパスが存在しません" >&2
      FAILED=1
    fi
  done < <(grep -n -o '`[^`]*`' "$doc")
}

self_test() {
  local tmp
  tmp="$(mktemp -t check-doc-citations)"
  trap 'rm -f "$tmp"' RETURN
  cat > "$tmp" <<'EOF'
行番号引用: `site/src/views/shared.tsx:13`
複数行の引用: `site/src/routes/public.tsx:20,33,106-128`
存在しないパス: `BefoldApp/befold/App/NoSuchFile.swift`
実在するパス: `BefoldApp/project.yml`
ファイル名だけの実在引用: `viewer.html`
シンボル名(検査対象外): `DOWNLOAD_URL`
EOF
  local out
  out="$(FAILED=0; check_doc "$tmp" 2>&1 1>/dev/null || true)"
  local case_name pattern
  while IFS='|' read -r case_name pattern; do
    echo "$out" | grep -q -- "$pattern" \
      || { echo "self-test 失敗: $case_name を検知できませんでした" >&2; echo "$out" >&2; return 1; }
  done <<'EOF'
行番号引用|shared.tsx:13
複数行の行番号引用|public.tsx:20,33,106-128
存在しないパス|NoSuchFile.swift
EOF
  while IFS='|' read -r case_name pattern; do
    echo "$out" | grep -q -- "$pattern" \
      && { echo "self-test 失敗: $case_name を誤検知しました" >&2; echo "$out" >&2; return 1; }
  done <<'EOF'
実在するパス|project.yml
ファイル名だけの実在引用|viewer.html
シンボル名|DOWNLOAD_URL
EOF
  echo "self-test OK: 行番号引用と存在しないパスを検知し、実在パスとシンボル名は通過しました"
}

if [ "${1:-}" = "--self-test" ]; then
  self_test
  exit $?
fi

if [ "$#" -gt 0 ]; then
  DOCS=("$@")
else
  DOCS=()
  while IFS= read -r d; do DOCS+=("$d"); done < <(find "$ROOT/docs/adr" "$ROOT/docs/dev" -name '*.md' | sort)
  # 既定の実行では毎回 self-test を通す。検知そのものが壊れた場合に、グリーンのまま
  # 何も見ていない状態になるのを防ぐ。
  self_test > /dev/null || { echo "check-doc-citations.sh の self-test が失敗しました" >&2; exit 1; }
fi

for doc in "${DOCS[@]}"; do
  check_doc "$doc"
done

if [ "$FAILED" != 0 ]; then
  cat >&2 <<'EOF'

docs/adr/** と docs/dev/** は「今のコード」を語る層です（CLAUDE.md「設計文書の三層構造」）。
コードを指すときは行番号を書かず、パスとシンボル名で示してください。
  NG: `DOWNLOAD_URL`（`site/src/views/shared.tsx:13`）
  OK: `DOWNLOAD_PATH`（`site/src/views/shared.tsx`）
当時の位置を記録として残したい文書は docs/superpowers/ 配下（スナップショット層）へ置いてください。
ADR の Context が「当時あったが今は無いファイル」を名指しする場合や、例示のための
架空名・リポジトリ外のオブジェクトキーは scripts/doc-citation-allowlist.txt に
「文書パス|引用」の形で追記してください。
EOF
  exit 1
fi
