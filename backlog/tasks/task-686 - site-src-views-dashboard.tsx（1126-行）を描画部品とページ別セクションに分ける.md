---
id: TASK-686
title: site/src/views/dashboard.tsx（1126 行）を描画部品とページ別セクションに分ける
status: To Do
assignee: []
created_date: '2026-10-08 09:35'
updated_date: '2026-10-08 09:35'
labels:
  - site
  - refactor
dependencies:
  - TASK-684
  - TASK-685
references:
  - site/src/views/dashboard.tsx
  - site/src/routes/dashboard.tsx
priority: medium
type: chore
ordinal: 875000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`site/src/views/dashboard.tsx` は 1126 行で、TASK-684 で TS 側にファイルサイズの上限を lint で持たせるときの超過一覧の 2 番目にある。analytics.ts と同じく、上限の override 除外から外せる形に分ける。

## 現状の混在（2026-10-08 実測）

- **文字列定数**: `STREAM_SCRIPT`（イベントストリームのクライアント JS）、`STYLE`（ダッシュボード全体の CSS）、`*_START` 系の計測開始日
- **汎用の描画部品**: `CountTable` / `RouteTable` / `GroupedBarChart` / `SeriesChart` / `Legend` / `Cards` / `metricCards` / `splitRows` / `formatLastSeen`。ページに依存しない
- **ページ別セクション**: `OverviewSections` / `UsersSections` / `TrafficSections` / `DeliverySections` / `EventsSections`（各 100〜160 行）と `renderOverviewSections`
- **外枠**: `DashboardPageShell`

## 利用側

import しているのは `src/routes/dashboard.tsx` と `test/dashboard.test.ts` の 2 ファイルだけ。export は `*Sections` 5 つと `renderOverviewSections` / `DashboardPageShell` の 7 つ。

分割の境界は着手時に決める。analytics.ts 側（別タスク）が型・ラベルの置き場を動かす場合、こちらの import 先も変わるので、先に着手するほうが後の付け替えを 1 回で済ませられる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TASK-684 が決めた閾値に対し、views/dashboard.tsx 由来のモジュールを override の一時除外から外しても `npm run lint` が通る
- [ ] #2 `routes/dashboard.tsx` の import 先が変わるだけで、各ページの HTML 出力は変わらない（`test/dashboard.test.ts` が変更なしに通る、または import パスの書き換えだけで通る）
- [ ] #3 ページに依存しない描画部品（表・チャート・カード）が、ページ別セクションとは別のモジュールにある
- [ ] #4 各モジュールの先頭コメントに「何を置くか／置かないか」が 1〜2 行で書かれている
- [ ] #5 site/.oxlintrc.json の override から views/dashboard.tsx のエントリが消えている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手順: TASK-685（analytics.ts）が型・ラベルの置き場を動かすと、こちらの import 先が変わる。付け替えを 1 回で済ませるため TASK-685 を先に片付ける（依存で表現済み）。
<!-- SECTION:NOTES:END -->
