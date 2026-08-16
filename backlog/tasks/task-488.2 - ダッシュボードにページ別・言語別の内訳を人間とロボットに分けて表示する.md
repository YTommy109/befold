---
id: TASK-488.2
title: ダッシュボードにページ別・言語別の内訳を人間とロボットに分けて表示する
status: To Do
assignee: []
created_date: '2026-08-16 01:44'
updated_date: '2026-08-16 01:50'
labels: []
milestone: m-7
dependencies:
  - TASK-488.1
parent_task_id: TASK-488
priority: medium
ordinal: 719000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488 の表示側。記録は TASK-488.1 が用意する。

TASK-488.1 で `events` に入ったページ・言語の情報を、ダッシュボード（`site/src/views/dashboard.tsx`）に内訳として出す。人間とロボットの分離は既存の仕組みに合わせる。集計は `site/src/analytics.ts` の `HUMAN_ONLY`（`:146`）を使い、ボット除外条件を新しく書かない（1 箇所集約は規約テスト `site/test/analytics.test.ts:299` が担保）。表示形式は既存の「人間の訪問とロボットの巡回」セクション（`site/src/views/dashboard.tsx:350-369`）を参考にする。

既存行はページ・言語が NULL で遡及分類できないため、同ダッシュボードに既にある「遡及分類不可」の注記と同じ形で示す。

`summarize()` の発行クエリ数には上限テストがある（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。指標ごとに 1 クエリ増やす作りにせず、既存の `metricBreakdown`（`site/src/analytics.ts:364-397`）のように `ROW_NUMBER() OVER (PARTITION BY ...)` でまとめる方針を検討する。SSE の差分配信（`site/src/analytics.ts:454-478`）にも新しい内訳が反映されること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 / と /features の参照数が区別して表示される
- [ ] #2 日本語で読んでいる人と英語で読んでいる人の別が表示される
- [ ] #3 ページ別・言語別のどちらの内訳も人間とロボットに分けて表示される
- [ ] #4 ボット除外条件が新規に書かれておらず、既存の HUMAN_ONLY に集約されたままである
- [ ] #5 遡及分類できない既存行についての注記が表示されている
- [ ] #6 summarize のクエリ数が上限テストの範囲に収まっている
- [ ] #7 SSE による更新でも新しい内訳が反映される
- [ ] #8 dashboard のテストが新しい内訳の描画と 0 件時の挙動を検証している
<!-- AC:END -->
