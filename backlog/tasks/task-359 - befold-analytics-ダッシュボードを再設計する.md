---
id: TASK-359
title: befold analytics ダッシュボードを再設計する
status: To Do
assignee: []
created_date: '2026-08-08 04:55'
updated_date: '2026-08-08 06:32'
labels:
  - site
  - analytics
dependencies: []
priority: high
ordinal: 618000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布サイトの analytics ダッシュボード (site/src/views/dashboard.tsx, site/src/analytics.ts) を、指標の定義・ページ構成・レイアウトごと再設計する。

現状の問題（実測・コード参照）:
- 「ユニーク訪問者（日次）」カード (views/dashboard.tsx:88) の実体は analytics.ts:52-60 の `COUNT(DISTINCT visitor_day)` で、WHERE も GROUP BY も無い全期間集計。visitor_day は sha256(ip+ua+UTC日付) (src/lib/visitor.ts:12-16) なので日ごとに別ハッシュになり、この値は「全期間の 訪問者×日 の延べ数」。日が経つほど単調増加し、日次でも累計ユニークでもない。
- 日付条件があるのは dailyDownloads() (analytics.ts:84-88) の 14 日窓だけ。breakdown()（version/country/os/referrer/as_org）も totals() も全期間。
- 日付バケットは date(ts/1000,'unixepoch') = UTC だが、最新イベント表の時刻表示は JST。visitor_day のハッシュ日付も UTC。表示基準がそろっていない。
- 期間フィルタ UI・日付ピッカーが無い。
- グラフ描画は一切無い（チャートライブラリ・canvas・SVG いずれも不在）。時系列は表の数値行のみ。

欲しい構成:
- 全体総数のエリア（累計）
- 日次総数のエリア（当日）
- 日毎の推移グラフ
- アクセス時刻（時間帯）の分布グラフ

events テーブルには ts (epoch ms, UTC) と idx_events_ts / idx_events_kind があり、日別・時刻別集計に必要な材料はそろっている (site/schema/schema.sql:4-20)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 累計 / 当日 / 日毎の推移 / 時間帯分布 の 4 領域が、それぞれ何を数えた値か画面上のラベルから一意に読み取れる
- [ ] #2 「日次」と表示される指標が実際に当日のみを集計している（全期間の延べ数を日次と表示している現状が解消されている）
- [ ] #3 日付・時刻の基準タイムゾーンが全指標で JST に統一され、JST 基準である旨が画面に明示されている
- [ ] #4 日毎の推移と時間帯分布がグラフとして描画される
- [ ] #5 SSE によるライブ更新が再設計後の構成でも機能する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-08 ユーザー判断: 全指標のタイムゾーン基準は JST。詳細は TASK-359.1 の Notes を参照。

2026-08-08 Acceptance Criteria が TZ 未確定版と JST 確定版で重複していたため JST 確定版へ一本化した（重複解消のみ）。
<!-- SECTION:NOTES:END -->
