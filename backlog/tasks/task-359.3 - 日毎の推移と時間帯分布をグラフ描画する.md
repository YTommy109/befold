---
id: TASK-359.3
title: 日毎の推移と時間帯分布をグラフ描画する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 04:56'
updated_date: '2026-08-08 06:44'
labels:
  - site
  - analytics
dependencies:
  - TASK-359.1
parent_task_id: TASK-359
priority: high
ordinal: 621000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在ダッシュボードにグラフ描画は一切なく（チャートライブラリ・canvas・SVG いずれも不在）、時系列は表の数値行のみ。日毎の推移と時間帯（0-23 時）分布をグラフで描く。ダッシュボードは外部アセットを読み込まない自己完結 HTML なので、CDN のチャートライブラリは使えない。インライン SVG を自前で組む方針が既定線だが、着手時に方式を決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 日毎の推移がグラフとして描画され、日付と件数が読み取れる
- [x] #2 時間帯（0-23 時）別のアクセス分布がグラフとして描画される
- [x] #3 外部ホストへのリクエストを発生させない（インライン化されている）
- [x] #4 データ 0 件・1 点のみ・全値同一 のケースで描画が壊れない
- [x] #5 SSE による summary の innerHTML 全置換（views/dashboard.tsx:32-34）でグラフ DOM が破棄されても、更新後にグラフが再描画される（TASK-359.1 からの申し送り）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. グラフはサーバ側でインライン SVG として描く（クライアント JS で描かない）
   - SSE の innerHTML 全置換で置き換わる HTML そのものがグラフになるため、再描画フックが構造的に不要になり AC #5 を担保できる
   - 外部ホストへのリクエストも発生しない（AC #3）
2. views/dashboard.tsx に BarChart コンポーネントを足す
   - viewBox + width:100% でレスポンシブに、色は currentColor 系でライト/ダーク両対応
   - 棒の高さは count / max。max === 0（全 0）で NaN になるため分岐する。0 件・1 点のみ・全値同一を明示的に扱う（AC #4）
   - role=img と aria-label を付ける
3. 日毎の推移（14 日）と時間帯分布（0〜23 時）にグラフを添える。数値の読み取りは既存の表を残して担保する
4. dashboard.test.ts に、SVG が出ること・SSE 配信 HTML にも含まれること・全 0 のケースで壊れないことのテストを足す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-08 実装完了。

方式: グラフはサーバ側でインライン SVG として描く（BarChart コンポーネント）。クライアント JS で描く方式を採らなかったのは、SSE が #summary を innerHTML で丸ごと置き換えるため、再初期化フックを別に用意する必要が生じ、書き忘れれば静かにグラフが消えるため。サーバ描画なら置き換わる HTML そのものがグラフになり、AC #5 が構造で満たされる（テストでも SSE 配信 HTML に SVG が含まれることを固定した）。

縮退ケース（AC #4）:
- 全値 0: max === 0 で count / max が 0 除算になるため棒を描かず軸だけ残す。系列の合計が 0 なら SeriesTable が「期間内のデータなし」を出すので、実際にはグラフ自体が描かれない
- 1 点のみ・全値同一: max と各値が等しく、棒はプロット高さいっぱい（126 = 140 - 14）になる。テストで height=\"126\" を確認
- テストで NaN が出力に含まれないことを検証

その他:
- 色は currentColor + opacity で指定し、color-scheme: light dark の両方に追従する
- role=\"img\" と aria-label（最大値つき）、各棒に <title> を付けた
- 数値の正確な読み取りは既存の表を残して担保し、グラフは概形の把握に使う
- 日付ラベルは MM-DD、時刻ラベルは 2 桁に短縮し 3 本に 1 つだけ描く

検証: npx vitest run で 74 passed / 6 files（新規 4 件）、npx tsc --noEmit エラーなし。
未検証: 実ブラウザでの見え方（16rem 幅のカラムに 24 本の棒を入れたときのラベルの可読性）。デプロイ前に目視が必要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
日毎の推移（14 日）と時間帯分布（0〜23 時）をインライン SVG の棒グラフで描画した。クライアント JS ではなくサーバ側で SVG を描くことで、SSE の innerHTML 全置換後も再描画フック無しでグラフが残る（AC #5 を構造で担保）。全値 0 での 0 除算、1 点のみ・全値同一を明示的に扱い、テストで NaN が出ないことと棒の高さを検証。外部ホストへのリクエストが無いこともテストで固定。vitest 74 件 pass、tsc エラーなし。
<!-- SECTION:FINAL_SUMMARY:END -->
