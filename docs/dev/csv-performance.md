# CSV viewer の性能計測

<!-- constrained-by ./rules/testing.md -->
<!-- derived-from ./viewer-rendering-dataflow.md -->

検索・描画の正しさは `BefoldApp/viewer-test/` の Jest で固定し、WebKit のレイアウトを
含む所要時間は `scripts/benchmark-csv.swift` で別に測る。既存の
`scripts/webview-smoke.swift` と同じ独立 WKWebView の形で、本番の HTML・CSS・bundle を読む。
時間の閾値を通常のテストや CI に追加しない。

## 入力と実行

Python 3 の標準ライブラリだけで、約 7 MB・18,222 レコード（ヘッダー込み）・13 列の
架空 CSV を作る。長文、空欄、引用符、カンマ、非 ASCII 文字、CRLF、約 14,000 個の
相対パスを含む。実データを読まず、URL は予約ドメイン `example.invalid` を使う。
生成物と測定結果は既存の gitignore 対象 `sample/large/` と `.tmp/` に置く。

macOS のログイン中のデスクトップで、リポジトリのルートから実行する。
viewer を編集した場合は先に `BefoldApp/` で `npm ci` と `npm run build:viewer` を実行する。

```sh
python3 scripts/make-large-csv.py --self-test
python3 scripts/make-large-csv.py
mkdir -p .tmp/csv-perf
swiftc -module-cache-path .tmp/csv-perf/swift-cache \
  scripts/benchmark-csv.swift -o .tmp/csv-perf/benchmark-csv
.tmp/csv-perf/benchmark-csv BefoldApp/BefoldKit/Resources \
  sample/large/manifest-synthetic.csv rendered > .tmp/csv-perf/table.jsonl
.tmp/csv-perf/benchmark-csv BefoldApp/BefoldKit/Resources \
  sample/large/manifest-synthetic.csv source > .tmp/csv-perf/source.jsonl
.tmp/csv-perf/benchmark-csv BefoldApp/BefoldKit/Resources \
  sample/large/manifest-synthetic.csv source true > .tmp/csv-perf/source-numbered.jsonl
```

CSV の**全件**を `render()` に渡す。アプリの初期 1,000 行やファイル読み込み処理の計測ではない。
表、ソース、行番号付きソースを分けて測る。検索は `s` → `sa` → `sample` → 不一致 → 空欄の順で、
多数一致、絞り込み、解除を通す。任意の UTF-8 CSV も同じ引数で使えるが、公開する入力には
架空データを使い、元データや置換対応表をコミットしない。
検索が遅すぎて完走できない比較対象では、前後の両方に `--render-only` を付けて描画だけを測る。

## 前後比較

<!-- derived-from #入力と実行 -->

比較対象の Resources を別ディレクトリへ取り出し、**同じ実行ファイル・同じ CSV**を渡す。
たとえば、変更前のコミットを `BASE_REF` に指定する。

```sh
BASE_REF=419ad83a
mkdir -p .tmp/csv-perf/before
git archive "$BASE_REF" BefoldApp/BefoldKit/Resources | tar -x -C .tmp/csv-perf/before
.tmp/csv-perf/benchmark-csv .tmp/csv-perf/before/BefoldApp/BefoldKit/Resources \
  sample/large/manifest-synthetic.csv rendered > .tmp/csv-perf/before-table.jsonl
```

同じ Mac・OS・表示設定で、前後を交互に各 3 回以上、1 プロセスずつ実行する。
別のビルドや WebKit 計測を並走させない。PR や調査記録には対象コミット、入力の SHA-256、
モード、行番号設定、回数、中央値と最大値を残す。生成器は入力のサイズ・構造・検索語の件数を出力し、
計測器は入力と Resources の SHA-256、OS、WebKit user agent、viewport、visibility を JSONL に記録する。

## 数値と検証の範囲

<!-- constrained-by ./rules/testing.md#unit--integration-の分離 -->

- `workMs`: `await render()`、または検索 input イベントの経過時間。処理内のレイアウトや await 待機も含む。
- `layoutMs`: 直後の `getBoundingClientRect()` による未処理レイアウトの時間。比較値は `workMs + layoutMs`。
- `frameMs`: 未計測を示す `null`。画面への提示、スクロールの滑らかさ、アプリ全体の応答時間とは区別する。
- 行数、本文長、パス注釈、検索件数、mark と native highlight の数も記録する。検索中に本文・行数が
  変わる、件数が一致しない、描画エラーが出る場合は非ゼロ終了する。検証は計測区間の外で行う。

新旧で本文長・行数・検索件数を照合してから時間を比較する。検索の検証は初期 DOM を基準にするため、
その行数・本文長が入力全体に対応することも別途確認する。パス注釈数は旧 mark 経路では変わり得るため
記録値として扱う。ビューの読み込み失敗・WebKit 終了・180 秒のタイムアウトも失敗扱い。
速度の改善だけでは、選択、正規表現、追記、ズーム、印刷、旧 WebKit のフォールバックの回帰テストを代替しない。
