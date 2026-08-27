---
id: TASK-557
title: CSV/TSV の数値列を読みやすく表示する
status: To Do
assignee: []
created_date: '2026-08-27 04:18'
labels: []
dependencies: []
ordinal: 805000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV/TSV のテーブル表示で、数値の列を右寄せし、量を表す列には桁区切りを入れ、会計用途向けに負の数の表現を選べるようにする。

現状 `viewer-src/csv-html.ts` の `csvRowsHtml` はセルを `escapeHtml` してそのまま `<td>` に入れるだけで、型判定・整形は Swift 側にも TS 側にも存在しない。桁の揃わない数値列は読み取りづらい。

befold はオープンソースで配布先のユーザー層が不明なため、判定は「当たれば嬉しい」ではなく「外さない」を優先する。郵便番号や商品コードに桁区切りを入れる誤りは、金額に桁区切りが入らない取りこぼしよりはるかに悪い。逃げ道としてソース表示（⌘2 の `csv-source`）が無加工の原文を見せているので、per-file の設定と永続化は今回作らない。

サブタスクに分割する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 数値列が右寄せかつ桁が揃って表示される
- [ ] #2 コードとみなせる列（郵便番号・商品コード・年・行番号など）に桁区切りが入らない
- [ ] #3 負の数の表現を Preferences から切り替えられる
<!-- AC:END -->
