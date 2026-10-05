---
id: TASK-668
title: CSV/TSV の列フィット（fitColumn）の所要時間を行数別に実測する
status: Done
assignee:
  - '@claude'
created_date: '2026-10-05 22:50'
updated_date: '2026-10-05 23:20'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/pull/708'
priority: low
ordinal: 853000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #708 の `fitColumn` は読み込み済みの全行のセルをクローンして測るため、行数に比例して重くなる。PR 説明は 5,000 行超でも応答したと述べるが所要時間の記載はない。数値が無いまま上限の要否を決められない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 1,000 / 10,000 / 50,000 行程度でフィットの所要時間が実測され、Notes に数値で残っている
- [x] #2 許容できない遅さなら対象行数の上限などの対策を入れ、許容範囲なら「不要」と結論が Notes に残っている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実 WKWebView の独立ハーネスで fitColumn（本体をそのまま）を行数別に実測する（サブエージェント）
2. 遅ければ、測定表へ入れるセルを表示長の上位 N 個＋ヘッダーに絞る（全行を見る意味は保つ）
3. 修正後を同条件で再測定し、幅が全行測定と一致することも確認
4. テスト・仕様書を更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（修正前、macOS 27.0.1 の実 WKWebView、5 列・各行約 100 文字、5 回の中央値/最大 ms。列3=長文, 列0=ID）: 1,000 行 28/125・23/31、10,000 行 307/852・275/362、50,000 行 1,675/4,492・1,412/1,735。行数にほぼ線形で、10,000 行から 100ms 目安を大きく超える。未測定: render() 経由、ズーム、ダークモード、極端に長いセル。

対策: fitColumn の測定表へ入れるセルを表示長（全角 2）の上位 200 個＋ヘッダーに絞った（csv-resize.ts の fitCandidates）。修正後の実測（同ハーネス、列3 / 列0 の中央値 ms）: 1,000 行 15/13、10,000 行 120/111、50,000 行 617/555。修正前の約 40〜45%。選ばれた列幅は全行測定と全ケースで一致（差 0px）。
残る時間の内訳（10,000 / 50,000 行の中央値 ms）: 走査と順位づけ 10/52、測定表の構築〜offsetWidth 97/505、setWidth＋強制レイアウト 93/503。測定表の部分は 1 セルの空の表でも同じ時間で、本体テーブルの行数に比例する。probe を position:fixed・contain:strict・.csv-scroll の外に置いても変わらず、body 直下に置くと 2〜3ms だが本番 CSS が効かず幅が +128px ずれる（使えない）。原因の推測（#diagram-wrap 配下の CSS 適用による再計算）は未検証。
未対策（スコープ外、起票はユーザー判断）: 本体テーブルの再レイアウトそのものは行数に比例し、ドラッグ 1 move も 10,000 行で約 110ms、50,000 行で約 720ms かかる。未測定: render() 経由、ズーム、ダークモード、極端に長いセル。
検証: viewer-csv-resize 12/12、新規テストは修正を戻すと落ちる。Jest 688 tests 通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
fitColumn を実 WKWebView で行数別に実測し（10,000 行で約 0.3 秒、50,000 行で約 1.5 秒）、測定表へ入れるセルを表示長の上位 200 個＋ヘッダーに絞った。所要時間は約 40〜45% になり（10,000 行 約 0.12 秒、50,000 行 約 0.6 秒）、選ばれる幅は全行測定と一致。残る本体テーブルの再レイアウト（行数に比例、ドラッグ 1 move も同様）は未対策で Notes に数値を残した。
<!-- SECTION:FINAL_SUMMARY:END -->
