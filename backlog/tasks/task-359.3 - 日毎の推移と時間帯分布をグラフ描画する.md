---
id: TASK-359.3
title: 日毎の推移と時間帯分布をグラフ描画する
status: To Do
assignee: []
created_date: '2026-08-08 04:56'
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
- [ ] #1 日毎の推移がグラフとして描画され、日付と件数が読み取れる
- [ ] #2 時間帯（0-23 時）別のアクセス分布がグラフとして描画される
- [ ] #3 外部ホストへのリクエストを発生させない（インライン化されている）
- [ ] #4 データ 0 件・1 点のみ・全値同一 のケースで描画が壊れない
<!-- AC:END -->
