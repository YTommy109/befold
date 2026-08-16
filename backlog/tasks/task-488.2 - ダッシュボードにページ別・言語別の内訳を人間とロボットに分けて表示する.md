---
id: TASK-488.2
title: ダッシュボードにページ別・言語別の内訳を人間とロボットに分けて表示する
status: To Do
assignee: []
created_date: '2026-08-16 01:44'
updated_date: '2026-08-16 03:47'
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
- [ ] #2 ブラウザ言語設定（ja / en / other）の内訳が表示される
- [ ] #3 言語の内訳に「これはブラウザの言語設定であって実際に読まれた言語ではない」ことが分かる表示（ラベルまたは注記）がある
- [ ] #4 ページ別・言語別のどちらの内訳も人間とロボットに分けて表示される
- [ ] #5 ボット除外条件が新規に書かれておらず、既存の HUMAN_ONLY に集約されたままである
- [ ] #6 遡及分類できない既存行についての注記が表示されている
- [ ] #7 summarize のクエリ数が上限テストの範囲に収まっている
- [ ] #8 SSE による更新でも新しい内訳が反映される
- [ ] #9 dashboard のテストが新しい内訳の描画と 0 件時の挙動を検証している
- [ ] #10 最新イベント表で / と /features の visit が見分けられる（recentEvents / eventsAfter の SELECT に page が含まれている）
- [ ] #11 COALESCE(page, '/') を kind='visit' と同じ条件節の外で使っていない（page が NULL の download / update_check に '/' を与えないこと）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-488.1 からの申し送り（設計レビューで確定した論点を AC 化した）:
- 言語は Accept-Language 由来の**ブラウザ言語設定**であって表示言語ではない。LP は日英を同一 HTML に持ち localStorage の befold-lang 未設定なら常に日本語を表示するため、en 設定の初回訪問者も日本語を読んでいる（site/src/views/shared.tsx の LANG_SCRIPT）。旧 AC #2「日本語で読んでいる人と英語で読んでいる人の別」は事実と食い違うため書き換えた。
- events.page の NULL には「列の導入前の visit（LP のみ = '/' と読んでよい）」と「ページの概念が無い download / update_check」の 2 つの意味がある。COALESCE(page,'/') は kind='visit' と同じ条件節の中でしか使えない（site/schema/schema.sql の page 列コメント、site/src/analytics.ts の metricExpression）。
- 「ページアクセス」指標は page='/' に絞ってあり、/features は含まない。ページ別内訳はこの系列とは別に出すこと。
- 日次ユニーク訪問者・国別・参照元別・UA 内訳の母集団は /features を含む（ページで絞っていない）。
- recentEvents / eventsAfter は SELECT に page を持たないため、現状ダッシュボードの最新イベント表では / と /features の visit が見分けられない。
<!-- SECTION:NOTES:END -->
