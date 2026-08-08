#!/usr/bin/env bash
set -euo pipefail

# FeatureGate 配下のコードに触れているのに件名へ (gate) スコープが無いコミットを弾く。
#
# /release-notes stable は「件名に (gate) が付いているか」だけを見てリリースノートから
# 除外する。スコープが漏れると、stable では露出しない機能がノートに載る（実例あり）。
# 規約は .claude/CLAUDE.md に明文化済みだが 2 度漏れたため、機械的に強制する。
#
# commit-msg フックとして呼ばれる想定: $1 = コミットメッセージのファイル、$2 = ソース。

MESSAGE_FILE="${1:-}"
MESSAGE_SOURCE="${2:-}"

[ -n "$MESSAGE_FILE" ] || exit 0
[ "${ALLOW_MISSING_GATE_SCOPE:-}" != "1" ] || exit 0
# マージは差分がコミットの意図を表さない。fixup!/squash! は元コミットの件名を後で継ぐ。
[ "$MESSAGE_SOURCE" != "merge" ] || exit 0

SUBJECT="$(grep -v '^#' "$MESSAGE_FILE" | grep -v '^[[:space:]]*$' | head -n 1 || true)"
[ -n "$SUBJECT" ] || exit 0
case "$SUBJECT" in
  fixup!* | squash!* | amend!* | Merge\ * | Revert\ *) exit 0 ;;
  *\(gate\)*) exit 0 ;;
esac

# ゲート参照はプロダクトコードにしか無い（テストは両分岐を確かめるために参照するので除く）。
# FeatureGate.swift 自体の変更は、参照行が動かなくてもゲート作業とみなす。
GATE_FILES="$(git diff --cached --name-only --diff-filter=ACMR -- '*.swift' \
  | grep -v -E '(Tests/|TestSupport/)' || true)"
[ -n "$GATE_FILES" ] || exit 0

touches_gate() {
  case "$1" in
    */FeatureGate.swift) return 0 ;;
  esac
  git diff --cached -U0 -- "$1" | grep -q -E '^[+-].*FeatureGate\.'
}

TOUCHED=""
while IFS= read -r file; do
  [ -n "$file" ] || continue
  if touches_gate "$file"; then
    TOUCHED="$TOUCHED  $file"$'\n'
  fi
done <<< "$GATE_FILES"

[ -n "$TOUCHED" ] || exit 0

cat >&2 <<EOF
エラー: FeatureGate 配下のコードに触れていますが、件名に (gate) スコープがありません。

  件名: $SUBJECT
  ゲート参照を含む差分:
$TOUCHED
  例: feat(gate): 変更ファイル絞り込みのトグルボタンを追加する

  /release-notes stable は件名の (gate) だけを見て stable のノートから除外します。
  付け忘れると、stable では露出しない機能がリリースノートに漏れます。

  ゲート内外を両方触っている場合は、ゲート側の変更を別コミットへ分けてください
  （分けられない場合は、コミット全体を (gate) として扱い、ノートから漏れる方を防ぎます）。
  意図的に付けない場合: ALLOW_MISSING_GATE_SCOPE=1 git commit ...
EOF
exit 1
