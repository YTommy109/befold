---
id: TASK-557.1
title: 数値列を判定して右寄せと桁区切りを適用する
status: Done
assignee: []
created_date: '2026-08-27 04:19'
updated_date: '2026-08-27 06:43'
labels: []
dependencies: []
parent_task_id: TASK-557
ordinal: 806000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`viewer-src/csv-html.ts` に列単位の判定を入れ、テーブル表示に右寄せと桁区切りを反映する。この段階では Preferences を作らず、桁区切りは常時オンとして実装する（設定化は TASK-557.2）。

## 二段構えの判定

**第 1 段（右寄せ）**: 列の非空セルがすべて数値としてパースできるなら右寄せ + `tabular-nums`。ID や年でも右寄せは誤読を生まないので条件は緩くてよい。

**第 2 段（桁区切り）**: 第 1 段を満たし、かつ以下の拒否条件をすべてくぐった列だけ。

| 拒否条件 | 落とすもの |
| --- | --- |
| 1,000 以上の値が 1 つも無い | 整形が no-op。無条件でスキップ |
| 先頭ゼロのセルがある | 郵便番号・商品コード・社員番号 |
| 全セルが同じ桁数、かつ 4 桁以上 | 固定長コード |
| 4 桁整数が全部 1900〜2100 | 年 |
| 1 から始まる連番で全ユニーク | 行番号 |
| 既にカンマを含むセルがある | 整形済み／欧州式小数 `1.234,56` の誤処理回避 |
| ヘッダー名が否定語に一致 | 命名で分かるコード列 |

否定語は `id` / `_id` / `code` / `no` / `zip` / `tel` / `phone` / `year` / `番号` / `コード` / `郵便` / `電話` / `年`。

**肯定側のヘッダー名マッチ（`price` / `金額` 等）は使わない。** 網羅不能な上、当てにすると誤爆を増やす方向にしか働かない。

## 値は書き換えない

桁区切りは整数部への挿入のみ。小数部は原文のまま維持する（`1.50` を `1.5` にしない）。丸め・桁数の正規化は一切しない。区切り文字は `,` 固定でロケール非依存（`Intl.NumberFormat` は使わない）。

## チャンク対応

`viewer-src/render.ts` の `appendChunk` が巨大 CSV を分割追記するため、列全体を見てからの判定はできない。ヘッダー + 先頭 200 データ行で列ごとの判定を確定させ、`appendChunk` はその判定を再利用する。後続チャンクで前提が崩れても、被害は「桁区切りが残る」だけで誤った値は出ない。

## 既知の弱点

「全セルが同じ桁数で 4 桁以上」の拒否条件は行数の少ないファイルで誤爆する（3 行しかない金額列がたまたま全部 5 桁、など）。サンプル行数が閾値未満のときはこの条件を無効にするが、閾値に実測の根拠はない。実装時に決めた値と理由を Implementation Notes に残すこと。

`tokenizeCsvRows` が各セルを `{ value, raw }` で返し生テキストを保持しているため、先頭ゼロの判定はそのまま使える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 全セルが数値の列が右寄せかつ tabular-nums で表示される
- [x] #2 1,000 以上を含む量の列に桁区切りが入る
- [x] #3 拒否条件それぞれについて、単独で該当するデータで桁区切りが入らないことを検証するテストがある
- [x] #4 小数部が原文のまま維持される（1.50 が 1.5 にならない）
- [x] #5 チャンク追記された後続行にも先頭チャンクと同じ列判定が適用される
- [x] #6 ソース表示（csv-source）の出力は変わらない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer-src/csv-columns.ts を新設し、列判定を置く。classifyCsvColumn が { format, reason } を返し（reason は拒否条件の識別子）、analyzeCsvColumns が列ごとの CsvColumnFormat ('text' | 'numeric' | 'grouped') 配列を返す。ヘッダー + 先頭 200 データ行をサンプルとする。
2. 第 1 段: 非空セルが全て /^[+-]?\d+(\.\d+)?$/ にマッチ → 'numeric'。カンマを含むセル（整形済み・欧州式小数）はこの正規表現で 'text' に落ちるため、独立した拒否条件は置かない。
3. 第 2 段の拒否条件（reason 識別子）: no-large-value / leading-zero / fixed-width / year-range / row-number / header-word。fixed-width はサンプル 5 件未満で無効化する。
4. ヘッダー否定語: camelCase を割った英数トークンとの一致で {id, code, no, zip, tel, phone, year}（+ 末尾 _id）、日本語 {番号, コード, 郵便, 電話, 年} は部分一致。肯定側マッチは使わない。
5. csv-html.ts の csvRowsHtml(rows, minCols, formats) / buildTableHtml(rows, formats) は formats を**必須引数**にする（省略可能にすると渡し忘れが静かに全列 text になる）。numeric/grouped の td と th に class="csv-num"、grouped は整数部にのみ ',' を挿入し小数部は原文のまま。
6. 判定の持ち越しは DOM ではなく document-state.ts の _mmdCsvColumns（_mmdChunkTail と同型）。render() が分岐へ入る前に無条件でリセットし、_renderCsv が判定を戻り値で返して render() が記録する（_renderSource が shape を返すのと同型）。renderers 側から document-state を書かない。
7. style.css に #diagram-wrap.csv-body table td.csv-num / th.csv-num の text-align: right と font-variant-numeric: tabular-nums。
8. テスト: BefoldKit/Resources/__tests__ に列判定の単体テスト（拒否条件ごとに reason を突き合わせる）と、csvRowsHtml/buildTableHtml の出力テスト、チャンク追記が同じ formats を使うテスト。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- 列判定は新設の `viewer-src/csv-columns.ts` に置いた。`csv-html.ts` は既にトークナイザと HTML 組み立ての 2 責務を持っており、そこへ判定を足すと 3 つ目になるため（実装前の /review-design 指摘）。
- `classifyCsvColumn` は `{ format, reason }` を返す。拒否条件は単独では分離できない組み合わせがある（年の列は必然的に「全セル 4 桁で同じ桁数」にも該当する）ため、出力の有無だけでは AC #3 の「拒否条件それぞれ」を検証できない。reason を突き合わせることで条件ごとに測れるようにした。
- `csvRowsHtml(rows, minCols, formats)` / `buildTableHtml(rows, formats)` の formats は**必須引数**にした。省略可能にすると渡し忘れがコンパイルエラーにならず、初回描画とチャンク追記で静かに見た目が食い違う（TASK-319 と同型）。
- 判定の持ち越しは DOM ではなく `document-state.ts` の `_mmdCsvColumns`。`_renderCsv` が判定を戻り値で返し `render()` が記録する（`_renderSource` が shape を返すのと同型）。document-state の書き手を render() だけに保つため。

## 決めた値と理由

- **固定長コード条件を有効にする最小サンプル数 = 5**。行数の少ないファイルでは金額列がたまたま全部同じ桁数になることが普通に起きる（3 行の請求書など）。4 件以下で桁数が揃うのは偶然の側が濃いと見て 5 を下限にした。**実測の裏付けは無い**。テスト `サンプルが 5 件未満なら固定長の条件は効かない` がこの値を固定している。
- **判定サンプルは先頭 200 データ行**（タスク記載どおり）。

## 実測で分かった代償

- **1,000〜9,999 に収まる金額列は、行数が多いと桁区切りが入らない。** 「全セル同じ桁数かつ 4 桁以上」の拒否条件に必ず該当するため。テストデータを `1200 + i * 37`（全部 4 桁）で作ったところ実際に numeric 止まりになり、`* 500` へ変えて桁数を散らすまで grouped にならなかった。タスクが「既知の弱点」として挙げたのはサンプル行数側だったが、実際にはこちらのほうが当たりやすい。「外さない」優先の設計なので条件は緩めていない。
- **⌘F の本文検索で `1234` が `1,234` に当たらなくなる。** 桁区切りは DOM のテキストを書き換えるため。逃げ道はタスクが挙げているソース表示（⌘2）で、そちらは無加工の原文のまま（テストあり）。

## reset の担保について

`render()` の `_mmdCsvColumns.reset()` は、現状のディスパッチでは csv-table が必ず `_renderCsv` を通って入れ直すため無くても表示は変わらない（**実測: reset を外しても列判定のテスト 52 件は全通しした**）。落ちるテストが無いことを承知の上で残し、その旨をコード側のコメントにも書いた。実効的な担保は「csv-table は必ず _renderCsv を通る」という構造のほう。

## 検証

- `npx jest`: 13 suites / 620 tests 全通し（うち新規 `viewer-csv-columns.test.js` 52 件）
- `npm run lint`（oxlint --type-aware）/ `npm run format` / `npm run typecheck:viewer` / `npm run check:viewer-cycles`: いずれもゼロ件
- `npm run build:viewer` で viewer-bundle.js を再生成済み
- `xcodegen generate`: .xcodeproj に差分なし（Swift 側の追加ファイル無し）

## 追記: ヘッダーは寄せない（レビュー指摘）

当初は「右寄せの数字の上に左寄せの見出しが乗る形を避ける」として `<th>` にも `csv-num` を付けていたが、ユーザー指摘により**ヘッダーは従来どおりブラウザ既定の中央**へ戻した。寄せるのは本文のセル(`<td>`)だけ。`csvCellHtml` から tag 引数を落として td 専用にし、`buildTableHtml` の `<th>` は formats を見ない。style.css のセレクタからも `th.csv-num` を外し、復活したら落ちるアサートをテストに置いた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CSV/TSV のテーブル表示に列単位の書式判定を入れた。判定は viewer-src/csv-columns.ts へ分離し、第 1 段（全セル数値 → 右寄せ + tabular-nums）と第 2 段（6 つの拒否条件をくぐった列だけ桁区切り）の二段構え。判定は document-state の _mmdCsvColumns で保持し、チャンク追記が初回チャンクと同じ書式を使う。値そのものは書き換えず、桁区切りは整数部への挿入のみで小数部は原文のまま。検証は新規テスト 52 件を含む jest 620 件全通しと、lint / format / typecheck / 循環チェックのゼロ件。
<!-- SECTION:FINAL_SUMMARY:END -->
