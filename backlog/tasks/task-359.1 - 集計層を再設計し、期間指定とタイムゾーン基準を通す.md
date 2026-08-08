---
id: TASK-359.1
title: 集計層を再設計し、期間指定とタイムゾーン基準を通す
status: To Do
assignee: []
created_date: '2026-08-08 04:55'
updated_date: '2026-08-08 05:02'
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
- [ ] #6 累計・当日・日別推移・時間帯別の各集計が個別に取得でき、期間の絞り込みが SQL の WHERE / GROUP BY で行われている
- [ ] #7 日次ユニーク訪問者が当日分のみを数え、全期間の延べ数にならない
- [ ] #8 日付・時間帯のバケット境界がすべて JST (UTC+9) で切られている（SQL 側で '+9 hours' 相当の補正が入っている）
- [ ] #9 visitor_day のハッシュ日付 (src/lib/visitor.ts の dayKey) も JST 日付で生成され、集計側のバケット基準と一致している
- [ ] #10 JST 化の前後で visitor_day のハッシュが変わり過去データと連続しないことを、doc コメントまたは Notes に記録する
- [ ] #11 日付境界（JST の 0 時前後、N 日窓の端）を検証するテストがある
- [ ] #12 既存の idx_events_ts / idx_events_kind で新しいクエリが賄えるか確認し、追加インデックスが要るなら migration を追加する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-08 ユーザー判断: タイムゾーン基準は JST に統一する。集計の日付・時間帯バケットだけでなく、visitor_day のハッシュ日付 (src/lib/visitor.ts:12-16 の dayKey、現在は toISOString().slice(0,10) で UTC) も JST 日付へ変える。この変更を境に同一訪問者のハッシュが変わるため、切り替え日をまたぐ日次ユニークの連続性は失われる（過去データの遡及再計算はしない）。

2026-08-08 追加観点: events.ua_summary はダッシュボードから一切参照されていない（デッドカラム相当）。AI クローラ（GPTBot / ClaudeBot 等）からのアクセス量を可視化できれば、TASK-360 で見送った llms.txt の要否を推測でなく実測で判断できる。集計層に UA 別の内訳を持たせるか検討すること。
<!-- SECTION:NOTES:END -->
