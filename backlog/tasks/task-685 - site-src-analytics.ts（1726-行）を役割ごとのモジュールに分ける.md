---
id: TASK-685
title: site/src/analytics.ts（1726 行）を役割ごとのモジュールに分ける
status: Done
assignee: []
created_date: '2026-10-08 09:35'
updated_date: '2026-10-08 10:12'
labels:
  - site
  - refactor
dependencies:
  - TASK-684
references:
  - site/src/analytics.ts
  - site/src/routes/dashboard.tsx
  - site/src/views/dashboard.tsx
priority: medium
type: chore
ordinal: 874000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`site/src/analytics.ts` は TASK-498 の oxlint 導入時に 957 行で「意図して 1 モジュールにしてある」と記録されたが、ダッシュボードのページ分割（overview / users / traffic / delivery / events）と配信経路の集計が足されて 1726 行になった。TASK-684 で TS 側にファイルサイズの上限を lint で持たせるにあたり、超過一覧の筆頭にあるこのファイルを、上限の override 除外から外せる形に分ける。

## 現状の混在（2026-10-08 実測）

1 ファイルに性質の違う 4 種類が同居している。

- **ビューと共有する型・定数・ラベル**: `Count` / `MetricKey` / `KindCounts` / `*Summary` 型、`KIND_LABELS` / `UNIQUE_SOURCE_LABELS` / `RUNNING_VERSION_LABELS` / `DASHBOARD_PAGES`、`DAILY_WINDOW_DAYS` などの窓幅定数。`views/dashboard.tsx` が import しているのはほぼこの層
- **D1 への SQL クエリ**: 非 export の関数が 21 個と、`cumulativeTotals` / `todayTotals` / `dailySeries` / `hourlyDistribution` / `trafficSplit` / `eventBreakdowns` など export された async 関数。`METRIC_EXPR` の CASE 式もここ
- **ページ単位のまとめ**: `summarizeOverview` / `summarizeUsers` / `summarizeTraffic` / `summarizeDelivery`。上のクエリを組み合わせて `*Summary` を作る。`routes/dashboard.tsx` の入口
- **イベントストリームのページング**: `recentEvents` / `eventPage` / `parseEventCursor` / `eventsAfter` / `maxEventId`

## 利用側

import しているのは `src/routes/dashboard.tsx`、`src/views/dashboard.tsx`、`test/analytics.test.ts`、`test/dashboard.test.ts`、`test/query-count.test.ts` の 5 ファイル。`test/query-count.test.ts` はクエリ本数を数えるテストなので、分割でクエリの発行回数が変わらないことの検査として使える。

分割の境界は着手時に決める（上の 4 種類はあくまで観察であって設計ではない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 TASK-684 が決めた閾値に対し、analytics.ts 由来のモジュールを override の一時除外から外しても `npm run lint` が通る
- [x] #2 `routes/dashboard.tsx` と `views/dashboard.tsx` の import 先が変わるだけで、ダッシュボード各ページの表示内容と集計値は変わらない（`test/dashboard.test.ts` と `test/analytics.test.ts` が変更なしに通る、または import パスの書き換えだけで通る）
- [x] #3 D1 へのクエリ発行回数が分割前後で変わらない（`test/query-count.test.ts` が通る）
- [x] #4 各モジュールの先頭コメントに「何を置くか／置かないか」が 1〜2 行で書かれている
- [x] #5 site/.oxlintrc.json の override から analytics.ts のエントリが消えている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
分割: site/src/analytics.ts を site/src/analytics/ の 11 モジュール（shared / metrics / sources / access-class / totals / breakdowns / routes / delivery / users / events / summaries）と index.ts（公開名の再エクスポートのみ）へ。最大 227 行。import パスは変わらない。構造ガードのテストは vitest.config.ts が analytics/ 全モジュールを連結して読む形へ変更し、docs/dev/development.md の「1 ファイルに置く」記述を改めた。検証: npm run lint / format:check / tsc 通過、npm test 13 ファイル 440 件通過（analytics / dashboard / query-count はテスト変更なし）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
analytics.ts（1726 行）を役割別 11 モジュールに分割し、override の一時除外を撤去。lint・typecheck・site の全テスト（440 件）で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
