---
id: TASK-359.1
title: 集計層を再設計し、期間指定とタイムゾーン基準を通す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 04:55'
updated_date: '2026-08-08 06:39'
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
- [x] #1 累計・当日・日別推移・時間帯別の各集計が個別に取得でき、期間の絞り込みが SQL の WHERE / GROUP BY で行われている
- [x] #2 日次ユニーク訪問者が当日分のみを数え、全期間の延べ数にならない
- [x] #3 日付・時間帯のバケット境界がすべて JST (UTC+9) で切られている
- [x] #4 visitor_day のハッシュ日付 (src/lib/visitor.ts の dayKey) も JST 日付で生成され、集計側のバケット基準と一致している
- [x] #5 JST 化の前後で visitor_day のハッシュが変わり過去データと連続しないことを、doc コメントまたは Notes に記録する
- [x] #6 日付境界（JST の 0 時前後、N 日窓の端）を検証するテストがある
- [x] #7 既存の idx_events_ts / idx_events_kind で新しいクエリが賄えるか確認し、追加インデックスが要るなら migration を追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー（/review-design）の結論を反映した計画。

1. src/lib/jst.ts を新設し JST の定義を 1 箇所に集約する
   - JST_OFFSET_MS / jstDayKey(ts) / jstDayStart(ts) / jstWindowStart(now, days)
   - SQL 用バケット式を定数化: JST_DAY_EXPR, JST_HOUR_EXPR（'+9 hours' を各クエリへ直書きしない。書き忘れても SQL は valid で UTC の結果が静かに返るため）
   - views/dashboard.tsx:5-9 の JST_OFFSET_MS / formatJst をこのモジュールへ移す
2. src/lib/visitor.ts の dayKey を jstDayKey へ委譲する。test/visitor.test.ts:35 の UTC 前提アサートを JST へ更新する
3. src/analytics.ts を 4 集計へ再設計する
   - cumulativeTotals(db): kind 別総数 + visitorDays（訪問者×日の延べ数。名前で意味を固定する）
   - todayTotals(db, now): JST 当日 0:00 以降の kind 別総数 + uniqueVisitors（累計側と別名にし混用を型エラーにする）
   - dailySeries(db, now, days): JST 日バケットの kind 別カウント。窓の起点は jstDayStart(now) - (days-1)*24h（現状の now-14*24h ローリングは端が日境界に揃わない）
   - hourlyDistribution(db, now, days): JST 時刻バケット。0〜23 のゼロ埋めは集計層で行う
   - 期間の絞り込みは WHERE ts >= ? のみで行い idx_events_ts / idx_events_kind を効かせる
   - ua_summary の内訳（byUA）を追加する（AI クローラ可視化。TASK-360 で見送った llms.txt の要否判断材料）
   - 既存の全期間 breakdown() には手を入れない（悪化させないことだけ守る）
4. test/analytics.test.ts を新設する
   - 必須: 同一 ts を jstDayStart(TS 側) と JST_DAY_EXPR(SQL 側) に通し同じ日付になることを実 D1 で突き合わせる（2 実装のズレは片方だけでは落ちないため）
   - JST 0 時前後の境界、N 日窓の端、当日ユニークが全期間の延べにならないこと、時間帯 0〜23 のゼロ埋め
5. EXPLAIN QUERY PLAN を実 D1 で取り追加インデックスの要否を確認する。不要なら Notes に実測を記録する

申し送り（受け取り側の AC にする）:
- TASK-359.2: JST 化の切替日より前は visitor_day が UTC 日付ハッシュのままで日次ユニークが最大 2 倍に膨らむ。14 日窓に必ず入るため画面に注記を出すこと
- TASK-359.3: SSE は summary 要素を innerHTML で全置換する（views/dashboard.tsx:32-34）ためグラフ DOM が破棄される。SSE 更新後もグラフが再描画されること
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-08 ユーザー判断: タイムゾーン基準は JST に統一する。集計の日付・時間帯バケットだけでなく、visitor_day のハッシュ日付 (src/lib/visitor.ts:12-16 の dayKey、現在は toISOString().slice(0,10) で UTC) も JST 日付へ変える。この変更を境に同一訪問者のハッシュが変わるため、切り替え日をまたぐ日次ユニークの連続性は失われる（過去データの遡及再計算はしない）。

2026-08-08 追加観点: events.ua_summary はダッシュボードから一切参照されていない（デッドカラム相当）。AI クローラ（GPTBot / ClaudeBot 等）からのアクセス量を可視化できれば、TASK-360 で見送った llms.txt の要否を推測でなく実測で判断できる。集計層に UA 別の内訳を持たせるか検討すること。

2026-08-08 起票時の Acceptance Criteria が #1-#5（TZ 未確定版）と #6-#12（JST 確定版）で重複していたため、JST 確定版に一本化した（内容の追加・削除はなく、重複の解消のみ）。

2026-08-08 実装完了。

構成:
- src/lib/jst.ts を新設し JST の定義を集約（JST_OFFSET_MS / jstDayKey / formatJst / jstDayStart / jstWindowStart / jstDaysInWindow、SQL 用の JST_DAY_EXPR / JST_HOUR_EXPR）。views/dashboard.tsx にあった JST_OFFSET_MS / formatJst はここへ移した。
- src/lib/visitor.ts の dayKey を jstDayKey へ委譲。UTC → JST の切り替えで同一訪問者の visitor_day ハッシュが変わり、切り替え日をまたぐ日次ユニークが過去データと連続しないことを doc コメントに明記した（遡及再計算はしない）。
- src/analytics.ts: cumulativeTotals / todayTotals / dailySeries / hourlyDistribution の 4 集計。期間の絞り込みは WHERE ts >= ? のみ。日別のゼロ埋めと時間帯 0〜23 のゼロ埋めは集計層で行う。窓の起点は jstWindowStart（当日を含む直近 N 日、JST 日境界そろえ。旧実装の now - 14*24h は端が半端だった）。
- 累計側を visitorDays（訪問者 × 日の延べ数）、当日側を uniqueVisitors と別名にし、同じ SQL 断片が期間次第で別の意味になる問題を型で分離した。
- ua_summary の内訳 byUA を追加（AI クローラ実測用、TASK-360 の llms.txt 判断材料）。

インデックス確認（実測、EXPLAIN QUERY PLAN を実 D1 で取得）:
- todayTotals: SEARCH events USING INDEX idx_events_ts (ts>?)
- dailySeries: SEARCH events USING INDEX idx_events_ts (ts>?) + USE TEMP B-TREE FOR GROUP BY
- hourlyDistribution: SEARCH events USING INDEX idx_events_ts (ts>?) + USE TEMP B-TREE FOR GROUP BY
GROUP BY の TEMP B-TREE はバケットが式（date(...,'+9 hours')）のため。式インデックスを足せば消せるが、絞り込み後の行数が小さいため追加しない。**migration の追加は不要**と判断した。

既存テストへの波及（JST 化の直接の帰結）:
- test/visitor.test.ts の dayKey / visitorDayHash の UTC 前提アサートを JST 前提へ更新（JST 0 時をまたぐ 1 分差で別ハッシュになることを検証する形にした）
- test/dashboard.test.ts の見出し文言 2 箇所

検証: npx vitest run で 68 passed / 6 files（新規 test/analytics.test.ts の 11 件を含む）、npx tsc --noEmit エラーなし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
集計層を累計 / 当日 / 日別推移 / 時間帯分布の 4 つへ再設計し、日付・時間帯の基準を JST へ統一した。JST の定義は src/lib/jst.ts に集約し、SQL のバケット式も定数化して各クエリへの直書き（書き忘れても UTC の結果が静かに返る）を防いだ。visitor_day のハッシュ日付も JST へそろえ、TS 側の日付計算と SQL 側のバケット式が同じ日を指すことを実 D1 で突き合わせるテストで固定した。累計の延べ数と当日のユニーク数は型名を分けて混用を防いでいる。EXPLAIN QUERY PLAN の実測で新設クエリが idx_events_ts を使うことを確認し、追加インデックスは不要と判断。vitest 68 件 pass、tsc エラーなし。
<!-- SECTION:FINAL_SUMMARY:END -->
