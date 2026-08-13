---
id: TASK-470
title: CSV/TSV のセル内 \n エスケープシーケンスをテーブル表示で改行にする
status: To Do
assignee: []
created_date: '2026-08-13 07:37'
updated_date: '2026-08-13 07:38'
labels:
  - feature
dependencies: []
priority: medium
ordinal: 114800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
.csv / .tsv のセル値に含まれる 2 文字のエスケープシーケンス `\n`（バックスラッシュ + n）を、テーブル表示では実際の改行として描画したい。

## 現状（実コード確認済み）

- パースは JS 側の `BefoldApp/viewer-src/csv-html.js` の `tokenizeCsvRows`（RFC 4180 準拠の状態マシン）が単一の情報源。テーブル表示（`parseCsv` → `buildTableHtml` / `csvRowsHtml`）とソース表示（`csvSourceInnerHtml`）が同じトークナイザーを共有する。
- セルは `escapeHtml` を通した文字列連結で `<td>` に入る（`csv-html.js:100` 付近）。innerHTML 代入だがセル値はエスケープ済み。
- テーブルのセルは既に `white-space: pre-line`（`BefoldKit/Resources/style.css:654-657`）。つまり **セル値に実改行を入れさえすれば、追加の CSS なしでそのまま改行表示される**（RFC 4180 のクオート内改行が既にこの経路で表示できている）。
- したがって必要なのは「`\n` の 2 文字を実改行へ置き換える」1 箇所だけで、実現可能性は高い。

## 決める必要がある論点

1. **対象範囲**: テーブル表示のみか、ソース表示（Rainbow CSV）も含めるか。ソース表示は「ファイルの中身をそのまま見せる」性質なので、テーブル表示のみに限るのが素直（ソース表示で改行にすると行番号と実ファイルの行がずれる）。
2. **変換する記法**: `\n` だけか、`\t` / `\r` / `\\` も含めるか。
3. **`\\n` の扱い**: バックスラッシュ自体がエスケープされている場合（`\\n`）はリテラルの `\n` を表示すべき。単純な文字列置換ではなく、左から 1 パスで走査する unescape が要る。
4. **常時有効か切り替えか**: 常時有効にすると、`\n` をリテラルとして持つ正当なデータ（コード片・正規表現・Windows パス）が意図せず改行になる。表示オプションのトグルにする案も検討する。
5. **適用箇所**: `parseCsv` の value 生成時に変換すると `csvRowsHtml` / `buildTableHtml` の両方（初回描画とチャンク追記 `render.js:205`）に一度に効く。ソース表示は `raw` を使うので影響しない。この置き場所なら経路が 1 本に畳まれる。

## 参考

- 呼び出し元: `viewer-src/renderers.js:106`（初回描画）、`viewer-src/render.js:187,205`（チャンク追記）
- テスト: `BefoldKit/Resources/__tests__/viewer.test.js`（`csvRowsHtml` / `csvSourceInnerHtml` / `parseCsv` を直接 import している）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テーブル表示で、セル値中の `\n` が改行として描画される
- [ ] #2 ソース表示（Rainbow CSV）の見え方と行番号は従来どおり変わらない
- [ ] #3 `\\n` はリテラルの `\n` として表示され、改行にならない
- [ ] #4 初回描画とチャンク追記の両方の経路で同じ結果になる（jest テストで担保）
- [ ] #5 上記論点 1・2・4 の決定が Implementation Notes に記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
補足（調査で確認）: `BefoldKit/Resources/viewer-bundle.js` は手書きではなく `viewer-src/` を esbuild で束ねた生成物（package.json の `build:viewer`）。修正は `viewer-src/csv-html.js` に入れ、bundle を再生成すること。

Swift 側に CSV パーサは無い（`FileType.swift` が区切り文字を決めて `lang` として JS へ渡すだけ）ため、変更は JS 側で完結する。CSV は差分表示の対象外（`renderers.js` が type === 'csv' で空を返す）なので差分経路への波及も無い。
<!-- SECTION:NOTES:END -->
