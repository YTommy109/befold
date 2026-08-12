#!/usr/bin/env bash
set -euo pipefail

# 型グループ（`Foo.swift` + 同ディレクトリの `Foo+*.swift`）単位で行数を集計し、
# 閾値（400 行）以下であることを強制する。
#
# 背景(TASK-428): SwiftLint の `file_length` はファイル単位の判定なので、責務を分けずに
# ファイルだけ `Type+Feature.swift` へ割れば必ず通る。TASK-411 の Description が実例を
# 記録している —「すでに +Capabilities / +Diff / +WindowHelpers の 3 拡張が存在するが、
# これは同じ行数上限を回避するために切られたものであり責務の分離にはなっていない」。
# 合算で数えればこの逃げ道が塞がる。
#
# 判定は「行数 <= 閾値、または恒久例外の上限以下」のみ(TASK-428.5)。返済期間中の足場だった
# ベースライン方式（現状値を凍結して増加のみ禁止するラチェット）は撤去した。ベースラインが
# 残る限り「値を書き換えれば通る」逃げ道が構造として存在するため。例外は
# `scripts/type-group-exceptions.txt` に「グループキー・上限行数・理由」の 3 点で列挙する。
#
# 使い方:
#   scripts/check-type-group-size.sh              # 全グループを行数の降順で出力する
#   scripts/check-type-group-size.sh --over       # 閾値を超えたグループだけを出力する
#   scripts/check-type-group-size.sh --check      # 判定する（CI / pre-commit が使う）
#   scripts/check-type-group-size.sh --self-test  # 集計・グループ化・判定が正しいことを確認する

ROOT="$(git rev-parse --show-toplevel)"
SOURCE_DIR="${TYPE_GROUP_SOURCE_DIR:-$ROOT/BefoldApp}"

# 閾値は SwiftLint の `file_length` warning と同じ 400。合算単位なので緩めたくなるが、
# 「400 行の型は分割を検討する」という基準自体はグループでも変わらないため揃える。
THRESHOLD="${TYPE_GROUP_THRESHOLD:-400}"

EXCEPTIONS="${TYPE_GROUP_EXCEPTIONS:-$ROOT/scripts/type-group-exceptions.txt}"

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

# 閾値（と恒久例外の上限）を超えたグループを stderr へ報告する。
#
# 終了コード: 0 = 問題なし / 1 = 違反または例外エントリの形式不正 / 2 = 不要になった例外が残っている
#
# 不要な例外を違反にしない理由: 返済して閾値以下へ戻した瞬間にコミットが赤くなると、
# 分割作業の途中で `--no-verify` を常用する圧力になる。残っていても判定が緩むのは
# その 1 グループだけなので、警告に留めて掃除を促す。
enforce_threshold() {
  [ -f "$EXCEPTIONS" ] || { echo "エラー: 恒久例外ファイルがありません: $EXCEPTIONS" >&2; return 1; }
  collect | sort -k2,2 | awk -F'\t' -v t="$THRESHOLD" '
    # 1 ファイル目: 恒久例外。形式は <キー><TAB><上限><TAB><理由> の 3 列で、理由が空なら弾く。
    NR == FNR {
      if ($0 ~ /^#/ || $0 == "") next
      if (NF != 3 || $1 == "" || $2 !~ /^[0-9]+$/ || $3 ~ /^[[:space:]]*$/) {
        printf "例外の形式が不正です（<グループキー><TAB><上限行数><TAB><理由> の 3 列で、理由は必須）: %s\n", $0 > "/dev/stderr"
        malformed = 1
        next
      }
      limit[$1] = $2
      next
    }
    {
      key = $2; lines = $1
      if (key in limit) {
        seen[key] = 1
        if (lines > limit[key]) {
          printf "恒久例外の上限超過: %s が %d 行（上限 %d）\n", key, lines, limit[key] > "/dev/stderr"
          violated = 1
        } else if (lines <= t) {
          printf "不要な例外: %s は %d 行で閾値 %d 以下です。scripts/type-group-exceptions.txt から行を消してください\n", key, lines, t > "/dev/stderr"
          stale = 1
        }
      } else if (lines > t) {
        printf "閾値超過: %s が %d 行（閾値 %d）\n", key, lines, t > "/dev/stderr"
        violated = 1
      }
    }
    END {
      for (k in limit) {
        if (!(k in seen)) {
          printf "不要な例外: %s は集計結果にありません。scripts/type-group-exceptions.txt から行を消してください\n", k > "/dev/stderr"
          stale = 1
        }
      }
      if (malformed || violated) exit 1
      if (stale) exit 2
    }
  ' "$EXCEPTIONS" -
}

case "${1:-}" in
  --self-test)
    # GNU mktemp は `-t 名前` に XXXXXX を要求するため、テンプレートを明示して
    # macOS(BSD) と ubuntu(GNU) の双方で動く形にする（CI は ubuntu で走る）。
    tmp="$(mktemp -d "${TMPDIR:-/tmp}/type-group-self-test.XXXXXX")"
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
    # 判定。閾値を 4 に落とし、App/Foo(6 行) / Other/Foo(4 行) / App/URL(5 行) を相手に
    # 「閾値超過」「例外で許容」「例外の上限超過」「不要な例外」「理由なしの例外」を確認する。
    THRESHOLD=4
    EXCEPTIONS="$tmp/exceptions.txt"

    check_case() {
      local label="$1" want_status="$2" want_message="$3" out status=0
      out="$(enforce_threshold 2>&1 1>/dev/null)" || status=$?
      if [ "$status" != "$want_status" ]; then
        echo "self-test 失敗: $label の終了コードが $status（期待 $want_status）" >&2
        echo "$out" >&2
        fail=1
      elif ! echo "$out" | grep -q -F "$want_message"; then
        echo "self-test 失敗: $label のメッセージに「$want_message」がありません" >&2
        echo "$out" >&2
        fail=1
      fi
    }

    # 閾値超過: 例外が空なら App/Foo(6 行) と App/URL(5 行) が閾値 4 を超えて落ちる。
    printf '# comment\n' > "$EXCEPTIONS"
    check_case "閾値超過" 1 "閾値超過: App/Foo が 6 行（閾値 4）"

    # 例外で許容: 両方を上限付きで登録すると通る（終了コード 0）。
    printf 'App/Foo\t6\t理由\nApp/URL\t5\t理由\n' > "$EXCEPTIONS"
    status=0
    enforce_threshold > /dev/null 2>&1 || status=$?
    if [ "$status" != 0 ]; then
      echo "self-test 失敗: 例外で許容されるはずが終了コード $status" >&2
      enforce_threshold >&2 || true
      fail=1
    fi

    # 例外の上限超過: App/Foo の上限を 5 に下げると落ちる。
    printf 'App/Foo\t5\t理由\nApp/URL\t5\t理由\n' > "$EXCEPTIONS"
    check_case "例外の上限超過" 1 "恒久例外の上限超過: App/Foo が 6 行（上限 5）"

    # 理由なしの例外は形式不正として弾く。
    printf 'App/Foo\t6\nApp/URL\t5\t理由\n' > "$EXCEPTIONS"
    check_case "理由なしの例外" 1 "例外の形式が不正です"

    # 不要な例外: 閾値以下に戻ったグループ（Other/Foo は 4 行 = 閾値）の例外は警告。
    printf 'App/Foo\t6\t理由\nApp/URL\t5\t理由\nOther/Foo\t9\t理由\n' > "$EXCEPTIONS"
    check_case "不要な例外" 2 "不要な例外: Other/Foo は 4 行で閾値 4 以下です"

    # 集計結果に無いキーの例外も警告。
    printf 'App/Foo\t6\t理由\nApp/URL\t5\t理由\nApp/Gone\t9\t理由\n' > "$EXCEPTIONS"
    check_case "消滅した例外" 2 "不要な例外: App/Gone は集計結果にありません"

    [ "$fail" = 0 ] || exit 1
    echo "self-test OK: 合算・ディレクトリ分離・孤児 extension・excluded 除外と、閾値超過/例外で許容/上限超過/理由なし/不要な例外の判定を確認しました"
    ;;
  --check)
    status=0
    enforce_threshold || status=$?
    case "$status" in
      0) echo "型グループの行数は閾値以内です" ;;
      1)
        cat >&2 <<EOF

型グループ（Foo.swift + 同ディレクトリの Foo+*.swift の合算）の行数が閾値 ${THRESHOLD} を
超えています。ファイルを extension へ割っても合算値は減りません。責務を分けて別の型へ
切り出すか、不要なコードを削ってください。

どうしても閾値へ収まらない場合のみ、scripts/type-group-exceptions.txt へ
「グループキー<TAB>上限行数<TAB>理由」を追記します（理由の無いエントリは弾かれます）。
EOF
        ;;
      2)
        cat >&2 <<EOF

不要になった恒久例外が残っています。scripts/type-group-exceptions.txt から該当行を
削除してください。
EOF
        ;;
    esac
    exit "$status"
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
