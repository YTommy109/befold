#!/usr/bin/env bash
set -euo pipefail

# 型グループ（`Foo.swift` + 同ディレクトリの `Foo+*.swift`）単位で行数を集計する。
#
# 背景(TASK-428): SwiftLint の `file_length` はファイル単位の判定なので、責務を分けずに
# ファイルだけ `Type+Feature.swift` へ割れば必ず通る。TASK-411 の Description が実例を
# 記録している —「すでに +Capabilities / +Diff / +WindowHelpers の 3 拡張が存在するが、
# これは同じ行数上限を回避するために切られたものであり責務の分離にはなっていない」。
# 合算で数えればこの逃げ道が塞がる。
#
# このスクリプトは集計と出力だけを行う（判定・ブロックは後続サブタスクで足す）。
#
# 使い方:
#   scripts/check-type-group-size.sh              # 全グループを行数の降順で出力する
#   scripts/check-type-group-size.sh --over       # 閾値を超えたグループだけを出力する
#   scripts/check-type-group-size.sh --baseline   # ベースラインファイルの形式で出力する
#   scripts/check-type-group-size.sh --self-test  # 集計とグループ化が正しいことを確認する

ROOT="$(git rev-parse --show-toplevel)"
SOURCE_DIR="${TYPE_GROUP_SOURCE_DIR:-$ROOT/BefoldApp}"

# 閾値は SwiftLint の `file_length` warning と同じ 400。合算単位なので緩めたくなるが、
# 「400 行の型は分割を検討する」という基準自体はグループでも変わらないため揃える。
THRESHOLD="${TYPE_GROUP_THRESHOLD:-400}"

# 集計対象から外すのは `.swiftlint.yml` の `excluded` と同じ 2 つだけ。テストターゲットも
# `file_length` の対象なので、ここでも同じ扱いにする。
is_excluded() {
  case "$1" in
    */.build/* | */befold/Resources/*) return 0 ;;
    *) return 1 ;;
  esac
}

# 1 グループ 1 行で「行数<TAB>グループキー」を出力する。グループキーは
# `BefoldApp/befold/App/ViewerWindowController` のようなリポジトリ相対のディレクトリ + 型名。
#
# カウントは物理行数（`wc -l`）。SwiftLint の `file_length` は既定でコメント・空行も数える
# ため、物理行数を採ると閾値 400 の意味が両者で揃う。
#
# 本体 `Foo.swift` が無く `Foo+Bar.swift` だけがある孤児 extension（`URL+NormalizedPathKey`
# や `NSMenu+Items` のような外部型への拡張）も、同じ規則で `Foo` のグループとして数える。
# 本体の有無で扱いを変えると「本体を消してから extension を増やす」という逃げ道が残るため。
collect() {
  local file rel dir base key lines
  while IFS= read -r file; do
    is_excluded "$file" && continue
    rel="${file#"$ROOT"/}"
    dir="$(dirname "$rel")"
    base="$(basename "$rel" .swift)"
    # `Foo+Bar` は `Foo` へ畳む。`+` を含まない名前はそのまま。
    base="${base%%+*}"
    key="$dir/$base"
    lines="$(wc -l < "$file")"
    printf '%s\t%s\n' "$key" "$lines"
  done < <(find "$SOURCE_DIR" -name '*.swift' -type f) \
    | awk -F'\t' '{ total[$1] += $2 } END { for (k in total) printf "%d\t%s\n", total[k], k }'
}

format_sorted() {
  # 行数の降順、同数はキーの辞書順（出力を決定的にする）。
  sort -k1,1nr -k2,2
}

format_baseline() {
  # ベースラインはキーの辞書順で固定する。行数順にすると 1 グループの増減で無関係な行が
  # 動き、差分レビューで増減が読めなくなるため。
  sort -k2,2
}

case "${1:-}" in
  --self-test)
    tmp="$(mktemp -d -t type-group-self-test)"
    trap 'rm -rf "$tmp"' EXIT
    mkdir -p "$tmp/App" "$tmp/Other" "$tmp/befold/Resources"
    # 本体 + 同ディレクトリの extension 2 本 = 1 グループ（3 + 2 + 1 = 6 行）
    printf 'a\nb\nc\n' > "$tmp/App/Foo.swift"
    printf 'a\nb\n' > "$tmp/App/Foo+Bar.swift"
    printf 'a\n' > "$tmp/App/Foo+Baz.swift"
    # 別ディレクトリの同名は別グループ（合算しない）
    printf 'a\nb\nc\nd\n' > "$tmp/Other/Foo.swift"
    # 本体の無い孤児 extension も 1 グループとして数える
    printf 'a\nb\nc\nd\ne\n' > "$tmp/App/URL+Orphan.swift"
    # excluded は集計に含めない
    printf 'a\nb\nc\nd\ne\nf\ng\n' > "$tmp/befold/Resources/Excluded.swift"

    # ROOT はスクリプト冒頭で git から取るため、別プロセスでは差し替えられない。
    # 一時ツリーを指すよう変数を上書きして、集計関数を直接呼ぶ。
    ROOT="$tmp"
    SOURCE_DIR="$tmp"
    out="$(collect | format_sorted)"

    fail=0
    expect() {
      if ! echo "$out" | grep -q -x -F "$(printf '%b' "$1")"; then
        echo "self-test 失敗: 期待した行がありません: $1" >&2
        echo "--- 実際の出力 ---" >&2
        echo "$out" >&2
        fail=1
      fi
    }
    expect '6\tApp/Foo'
    expect '4\tOther/Foo'
    expect '5\tApp/URL'
    if echo "$out" | grep -q 'Excluded'; then
      echo "self-test 失敗: excluded 配下のファイルが集計に含まれています" >&2
      echo "$out" >&2
      fail=1
    fi
    if [ "$(echo "$out" | wc -l)" -ne 3 ]; then
      echo "self-test 失敗: グループ数が 3 ではありません" >&2
      echo "$out" >&2
      fail=1
    fi
    [ "$fail" = 0 ] || exit 1
    echo "self-test OK: 本体 + extension の合算・ディレクトリ違いの分離・孤児 extension・excluded の除外を確認しました"
    ;;
  --baseline)
    collect | format_baseline
    ;;
  --over)
    collect | format_sorted | awk -F'\t' -v t="$THRESHOLD" '$1 > t'
    ;;
  '')
    collect | format_sorted
    ;;
  *)
    echo "エラー: 不明な引数: $1" >&2
    exit 1
    ;;
esac
