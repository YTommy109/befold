# コードブロック表示にインデントガイド(縦線)を追加する

<!-- derived-from ../../../backlog/tasks/task-173 - コードブロック表示にインデントガイド縦線を追加する.md -->

> **これは 2026-07-27 時点の設計スナップショットです。**
> 現在の仕様は [`docs/dev/native-app-design.md`](../../dev/native-app-design.md)
> が単一の情報源。この文書は当時の意図と検討経緯を残すためのもので、
> 現在の実装と食い違っていることがある。着手前に必ずコードで裏を取ること。

## 背景

TASK-173。Zed / VS Code のように、ソースコード表示でインデントの深さを示す
縦のガイド線を表示したい。事前調査で以下が判明している。

- vendored highlight.js 単体にインデントガイド機能はなく、純粋 CSS だけでは
  折り返し時にガイド位置がズレる。
- 行番号なし表示は素の `<pre><code>` 単一ブロック、行番号あり表示は
  `buildLineNumberRows()` により 1 行ずつ `<tr><td class="line-content">` に
  DOM 分割されており、描画パスが二分している。
- `style.css` に `tab-size` 指定が一切ない(タブ/スペース混在でガイド間隔が崩れる)。

## 決定事項(ユーザー確認済み)

- **折り返し**: 「インデントに沿った折り返し」(ハンギングインデント)を採用する。
  折り返した継続行はその行のインデント位置に揃え、ガイド線は行ブロックの左パディング
  領域の背景として描くことで、折り返し行をまたいでもズレない。
- **tab 幅 / ガイド間隔**: `tab-size: 4`。ガイドは 4 桁ごとに引く。
- **ガイド範囲**: 各行自身の先頭インデント分だけ引く。空白のみ/空行はガイドなし。

## アーキテクチャ

コード描画を常に「行単位 DOM」へ一本化し、各行にインデント情報を CSS 変数で
付与して、CSS でガイド線とハンギングインデントを描く。算出ロジックは viewer.js の
純粋関数に置き、jest で検証する。WKWebView/CSS の見た目はリリース前スモークで確認する。

### 1. 描画パスの統一 (BefoldKit/Resources/viewer.js)

- `renderCodeHtml(hljs, str, lang, showLineNumbers)` の「行番号あり/なし」で
  出力構造が分かれる分岐を廃し、**常に行単位 DOM**(`buildLineNumberRows` 相当)を
  生成する。行番号セル `td.line-number` は `showLineNumbers` が真のときだけ出力する。
- 各行の `td.line-content` に、先頭空白から算出したインデント情報を CSS 変数で付与する。
  - `--indent-cols`: 先頭空白の桁数(タブは tab-size=4 の tab-stop まで、スペースは +1)
  - `--indent-depth`: `floor(--indent-cols / 4)` = 引くガイド本数
  - 空白のみ/空行は `--indent-depth: 0`
- チャンク追記経路(`buildLineNumberRows` を呼ぶ既存箇所)も同じ行生成関数を通す。

### 2. インデント算出 (純粋関数, viewer.js)

- `leadingIndentColumns(lineText, tabSize)`:
  先頭から空白を走査し、タブは次の tab-stop(`col + (tabSize - col % tabSize)`)まで、
  スペースは `+1` で桁数を進める。非空白に達したら終了して桁数を返す。空行は 0。
- 行 1 つを `<tr>...</tr>`(またはガイド用属性付き行要素)へ組み立てる関数に、
  `--indent-cols` / `--indent-depth` の付与を集約する。
- 上記関数群を `module.exports` に追加して jest 対象にする。

### 3. スタイル (BefoldKit/Resources/style.css)

- コード行に `tab-size: 4`(および `-moz-tab-size`)を明示する。
- ハンギングインデント:
  `td.line-content { padding-left: calc(var(--indent-cols, 0) * 1ch);
  text-indent: calc(var(--indent-cols, 0) * -1ch); white-space: pre-wrap; }`
  により、折り返し継続行がインデント位置に揃う。
- ガイド線: `td.line-content` の左パディング領域に `repeating-linear-gradient`
  (4ch ごとに 1px の縦線)を `background` として描く。`--indent-depth` に応じて
  描画範囲(`background-size` の横幅 = `calc(var(--indent-depth) * 4ch)`)を制御し、
  行自身のインデント分だけ・ブロック全高に引く。`--indent-depth: 0` の行は描かない。
- 色: 既存の `--fg-muted` を低不透明度で用いる(または `color-mix`)。
  ライト/ダーク両テーマで視認でき、既存シンタックスハイライト色と衝突しないこと。

### 4. テスト

- jest(`BefoldKit/Resources/__tests__/viewer.test.js`):
  - `leadingIndentColumns`: スペースのみ / タブのみ / タブ+スペース混在 /
    先頭非空白(0) / 空行(0) / タブが tab-stop 境界でない位置。
  - 行 HTML 生成: `--indent-cols` / `--indent-depth` が期待値で乗ること。
  - 行番号あり/なしで行構造(セル構成)が一致し、行番号セルの有無だけが差になること。
- 折り返し・ガイドの見た目、テーマ両対応は WKWebView スモーク(手動, リリース前)。

## 受け入れ基準(タスク AC との対応)

- AC#1(行番号あり/なし双方でガイド表示) → 描画パス統一 + CSS。
- AC#2(タブ/スペース混在でズレない) → `tab-size:4` + `leadingIndentColumns` の tab-stop 展開。
- AC#3(折り返しで崩れない) → ハンギングインデント + 左パディング背景ガイド。
- AC#4(ライト/ダークで視認・非衝突) → `--fg-muted` 低不透明度 + 両テーマ確認。

## スコープ外

- ガイド線のホバー強調やアクティブブロック強調(エディタ的な高度表示)。
- Markdown 本文中のインラインコードや `pre.mermaid`(除外済み)への適用。
- CSV ソース表示(別経路 `renderCsvSourceHtml`)。
