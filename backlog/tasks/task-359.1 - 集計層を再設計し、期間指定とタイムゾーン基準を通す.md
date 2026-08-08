---
id: TASK-359.1
title: 集計層を再設計し、期間指定とタイムゾーン基準を通す
status: To Do
assignee: []
created_date: '2026-08-08 04:55'
labels:
  - site
  - analytics
dependencies: []
parent_task_id: TASK-359
priority: high
ordinal: 619000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site/src/analytics.ts の集計関数群を、期間（累計 / 当日 / 直近 N 日）と時間帯を扱える形に再設計する。現状 totals() と breakdown() は全期間固定、dailyDownloads() だけが 14 日窓。日付バケットは UTC (date(ts/1000,'unixepoch')) だが表示は JST で不整合。visitor_day のハッシュ日付も UTC 基準 (src/lib/visitor.ts:12-16) なので、日次ユニークの定義を決める際はハッシュ側の基準とそろえる必要がある。集計層に analytics 単体のテストファイルが存在しないため、ここで用意する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 累計・当日・日別推移・時間帯別の各集計が個別に取得でき、期間の絞り込みが SQL の WHERE / GROUP BY で行われている
- [ ] #2 日次ユニーク訪問者が当日分のみを数え、全期間の延べ数にならない
- [ ] #3 日付バケットのタイムゾーン基準が visitor_day のハッシュ日付基準と一致している（不一致なら不一致であることを doc コメントで明示する）
- [ ] #4 日付境界（当日の開始・終了、N 日窓の端）を検証するテストがある
- [ ] #5 既存の idx_events_ts / idx_events_kind で新しいクエリが賄えるか確認し、追加インデックスが要るなら migration を追加する
<!-- AC:END -->
