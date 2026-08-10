---
id: TASK-423
title: 解析ダッシュボードの D1 クエリのファンアウトと全期間スキャンを減らす
status: To Do
assignee: []
created_date: '2026-08-10 07:29'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 509300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site/src/analytics.ts の summarize（:323-338）はダッシュボード 1 回の表示で約 19 本の D1 クエリを発行する。内訳は cumulativeTotals / todayTotals / dailySeries / hourlyDistribution / breakdown 3 本（version, country, referrer）/ uaSplit 3 本 / recent と、KIND_LABELS.map(kindBreakdown) による 4 × 2 = 8 本。

この 8 本は (kind, source, column) だけが違うほぼ同一の GROUP BY 全表スキャンで、`(?1 IS NULL OR kind = ?1) AND (?2 IS NULL OR COALESCE(source, "lp") = ?2)` という述語の形が idx_events_kind も効かなくする。breakdown 系はどれも期間で絞られていないため、ダッシュボードの応答時間と D1 の読み取り行数がイベント履歴の総量に比例して増え続ける。

8 本は (kind, source, os) と (kind, source, as_org) でグループ化した 2 本に畳める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 kind 別の内訳が 2 本以内のクエリで得られる
- [ ] #2 breakdown 系のクエリが期間で絞られる（または上限行数を持つ）
- [ ] #3 ダッシュボードの表示内容が変わらない
- [ ] #4 クエリ本数を実測して Implementation Notes に前後の値を残す
<!-- AC:END -->
