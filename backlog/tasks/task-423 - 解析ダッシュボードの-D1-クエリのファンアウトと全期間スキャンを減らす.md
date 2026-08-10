---
id: TASK-423
title: 解析ダッシュボードの D1 クエリのファンアウトと全期間スキャンを減らす
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 07:29'
updated_date: '2026-08-10 15:40'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 121000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site/src/analytics.ts の summarize（:323-338）はダッシュボード 1 回の表示で約 19 本の D1 クエリを発行する。内訳は cumulativeTotals / todayTotals / dailySeries / hourlyDistribution / breakdown 3 本（version, country, referrer）/ uaSplit 3 本 / recent と、KIND_LABELS.map(kindBreakdown) による 4 × 2 = 8 本。

この 8 本は (kind, source, column) だけが違うほぼ同一の GROUP BY 全表スキャンで、`(?1 IS NULL OR kind = ?1) AND (?2 IS NULL OR COALESCE(source, "lp") = ?2)` という述語の形が idx_events_kind も効かなくする。breakdown 系はどれも期間で絞られていないため、ダッシュボードの応答時間と D1 の読み取り行数がイベント履歴の総量に比例して増え続ける。

8 本は (kind, source, os) と (kind, source, as_org) でグループ化した 2 本に畳める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 kind 別の内訳が 2 本以内のクエリで得られる
- [x] #2 breakdown 系のクエリが期間で絞られる（または上限行数を持つ）
- [x] #3 ダッシュボードの表示内容が変わらない
- [x] #4 クエリ本数を実測して Implementation Notes に前後の値を残す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. summarize が発行する D1 クエリ本数を prepare のラッパで実測し、上限を検査するテストを先に落とす（実測 19 本）
2. 指標判定（kind × source）を METRIC_FILTERS から生成する SQL 式 METRIC_EXPR へ切り出す
3. kindBreakdown の 8 本を、指標を行に持たせた 2 本（os 別・as_org 別）へ畳む。指標ごとの上位 N 件は ROW_NUMBER() の窓で切る（LIMIT では 1 指標ぶんしか効かない）
4. breakdown の (?1 IS NULL OR kind = ?1) 形の述語を条件そのものの組み立てへ変え、kind を定数にして idx_events_kind が効く形へ戻す
5. 指標別内訳の分離（lp / sparkle）と上位 10 件打ち切りをテストで固定し、typecheck と全テストを通す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実測（クエリ本数）

test/query-count.test.ts が env.DB.prepare をラップして summarize 1 回ぶんを数える。

- 前: 19 本（assertion の実出力 `expected 19 to be less than or equal to 12`）
- 後: 13 本（同 `expected 13 to be less than or equal to 12` を経て上限 13 で確定）

減った 6 本は KIND_LABELS 4 指標 × (os, as_org) の 8 本を 2 本へ畳んだぶん。残る 13 本は
cumulativeTotals / todayTotals / dailySeries / hourlyDistribution / breakdown 3 本
（version・country・referrer）/ uaSplit 3 本 / recentEvents / 指標別内訳 2 本。
指標を増やしても 13 本のままになる（指標は行として返る）。

## 設計上の判断

- **指標判定の定義元を増やさない**: SQL 側の CASE 式 METRIC_EXPR を METRIC_FILTERS から
  生成する。lp / sparkle の対応を 2 箇所に書き写さないため。埋め込む値は定数だけで
  外部入力は入らない。
- **上位 N 件は ROW_NUMBER() の窓で切る**: 1 本に畳むと LIMIT は全体で 1 回しか効かず、
  指標ごとの上位 N 件にならない。
- **AC#2 は「上限行数を持つ」側で満たした**: breakdown 系は全期間の累計として表示して
  いるため、期間で絞ると AC#3（表示内容が変わらない）と衝突する。全クエリが明示的な
  行数上限（LIMIT 10 / ROW_NUMBER <= 10）を持つ形に統一した。読み取り行数自体は履歴の
  総量に比例するままで、これを下げるには集計テーブルの事前集約が必要（別タスク相当）。
- **ついでに述語の形も直した**: breakdown の `(?1 IS NULL OR kind = ?1)` は kind が
  定数にならず idx_events_kind が効かない。条件そのものを組み立てて外す形に変えた。

## 検証

- `npx tsc --noEmit` → No errors found
- `npx vitest run` → 9 files / 141 tests 全通過（既存の dashboard.test.ts を含む）
- 追加テスト: 指標別 OS/組織内訳が lp と sparkle で混ざらないこと、指標ごとに上位 10 件で
  打ち切られること、summarize のクエリ本数が上限 13 を超えないこと
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
指標別内訳を指標ごとの 8 本のクエリから、指標を行に持たせた 2 本（OS 別・接続元組織別）へ畳んだ。指標ごとの上位 10 件は ROW_NUMBER() の窓で切り、指標判定の CASE 式は METRIC_FILTERS から生成して定義元を 1 箇所に保つ。あわせて breakdown の (?1 IS NULL OR kind = ?1) 形の述語を条件の組み立てへ変え、kind が定数になり idx_events_kind が効く形に戻した。summarize 1 回のクエリ本数は 19 → 13 本（prepare をラップして実測、上限をテストで固定）。tsc --noEmit と vitest run（141 件）が全通過。
<!-- SECTION:FINAL_SUMMARY:END -->
