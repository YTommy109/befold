---
id: TASK-906.4
title: 印刷と PDF で CSV のセルが切り取られる
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:56:00Z'
updated_date: '2026-11-07T03:16:00Z'
labels: []
dependencies:
  - TASK-906.1
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: medium
type: bug
ordinal: 870000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
@media print は csv-sized も .csv-scroll も解除していない。csv-sized は従来、手動で幅を変えた後にだけ付いていたが、PR #748 ですべての CSV に付く。折り返して全文を印刷できていたセルが、切り取られたまま出力されるはず（コードからの判断、未実測）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 印刷と PDF で、従来全文が出ていたセルが切り取られない
- [x] #2 実際の印刷または PDF 出力で確認した結果が Notes にある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. @media print で csv-sized の固定レイアウトと切り取りを解除する（table-layout: auto、col の幅を解除、折り返しあり）
2. style.css のテストを足す
3. 実際に PDF を出力し、セルの全文が入ることを修正前後で比べる

/review-design: 項目 3（手動で幅を変えた表も印刷では自動にする。切り取らないことを優先）、7（@media print は jsdom で確認できないので実際の PDF で確認）。他は該当なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（アプリと同じ WKWebView.printOperation で PDF を出力し、PDFKit で本文を抽出。4 列 × 3 行、値は「word 」60 個 + 目印）: 修正前は目印 0 件・1 ページ、修正後は 9 セルすべての目印が入り 2 ページ。

判断: 手動で変えた幅も印刷では解除する。紙はスクロールできず、切り取らないことを優先した。

検証: jest 748 件成功（style.css の印刷規則を見るテストを追加）。@media print は jsdom で適用されないので、動作の確認は上の PDF による。

native-app-design.md への反映は不要（表示仕様は file-type-display.md を更新）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
印刷と PDF で CSV の列幅と切り取りを解除し、用紙の幅に収めて折り返すようにした。実際の PDF で 9 セルすべての全文が出ることを確認した（修正前は 0 セル）。

残るリスク: 手動で変えた幅は印刷に反映されない（切り取らないことを優先した判断）。
<!-- SECTION:FINAL_SUMMARY:END -->
