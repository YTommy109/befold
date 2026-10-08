---
id: TASK-667
title: CSV/TSV 列幅ハンドルの Tab ストップを列数ぶん増やさない
status: Done
assignee:
  - '@claude'
created_date: '2026-10-05 22:50'
updated_date: '2026-10-05 23:16'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/708'
priority: low
ordinal: 852000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #708 の列幅ハンドルは各ヘッダーに `tabIndex = 0` の `role="separator"` を置くため、100 列の CSV では Tab が 100 回ハンドルに止まる。実機の VoiceOver での挙動は未確認。`aria-valuemax` も付いていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ハンドルの Tab ストップが表全体で 1 つ（roving tabindex など）になり、左右キーで列間を移動できる、または現状維持の理由が Notes に残っている
- [x] #2 aria-valuemax を付けるか付けないかが決まっている
- [x] #3 選んだ挙動をテストで固定している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ハンドルの tabIndex を roving にする（先頭列のみ 0、focus したハンドルが 0 になり他は -1）
2. Alt+左右（macOS は Option）で隣の列のハンドルへフォーカス移動。左右キー単独のリサイズは維持
3. aria-valuemax は付けない（幅に上限が無い）。操作ヒント（en/ja）に移動キーを足す
4. テストと仕様書（キーボードの項）を更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
選んだ挙動: Tab で止まるのは表全体で 1 つ（roving tabindex）。移動は Alt+左右。aria-valuemax は付けない: 幅に上限が無く、上限を持たない値の separator は valuemax 省略とした。
未確認: 実機の VoiceOver での読み上げ・Option+矢印の衝突（WKWebView 内でテキスト選択移動に使われない前提）。コード上は preventDefault している。
実測: viewer-csv-resize 12/12、新規 2 件は roving と Alt 移動を戻すと落ちる（2 failed）。Jest 全体 688 tests 通過、tsc・oxfmt 通過。/review-design は局所修正のため省略。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CSV/TSV の列幅ハンドルの Tab ストップを表全体で 1 つにし（roving tabindex）、Alt+左右で隣の列へ移動できるようにした。aria-valuemax は付けない。ヒント文言（en/ja）と仕様書を更新。新規テスト 2 件は修正を戻すと落ちることを確認。Jest 688 tests 通過。実機 VoiceOver は未確認。
<!-- SECTION:FINAL_SUMMARY:END -->
