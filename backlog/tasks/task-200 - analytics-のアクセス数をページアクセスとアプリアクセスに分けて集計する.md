---
id: TASK-200
title: analytics ダッシュボードをページアクセスとアプリアクセスに分けて表示する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-30 13:12'
updated_date: '2026-07-30 13:26'
labels: []
dependencies:
  - TASK-182.7
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
priority: medium
ordinal: 272500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在のダッシュボードはアクセス数を単一の指標として見せているため、サイト閲覧とアプリ利用（ダウンロード・アップデート確認）を区別できない。計測側は TASK-182.7 までで既に visit / download / update_check の 3 種別イベントを OS・国・接続元組織（as_org）付きで events テーブルに記録しているため、本タスクはダッシュボードの集計・表示の変更が主となる（スキーマ変更は原則不要）。

表示は「ページアクセス（visit）」「ダウンロード（download）」「アップデート確認（update_check）」の 3 指標に分ける。ダウンロードは新規獲得、アップデート確認は継続利用を表す指標であり意味が異なるため、アプリアクセスとして合算せず個別に見せる。3 指標それぞれで OS 別・接続元組織別の内訳を確認できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ダッシュボードでページアクセス（visit）・ダウンロード（download）・アップデート確認（update_check）が それぞれ独立した指標として表示される
- [x] #2 3 指標それぞれの内訳を OS 別に確認できる
- [x] #3 3 指標それぞれの内訳を接続元組織（as_org）別に確認できる
- [x] #4 既存の合算アクセス数表示の扱い（残す／置き換える）が決められ、README または設計ドキュメントに記載される
- [x] #5 集計クエリに対するテストが site/ の既存テスト方針に沿って追加される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討: breakdown() は既に kind フィルタ引数を持つため、SQL の新設は不要。呼び出し回数を増やすだけで per-kind 集計が得られる。
2. analytics.ts: EVENT_KINDS（schema.ts の eventKindSchema.options を再利用）を追加し、Summary の合算 byOS / byAsOrg を perKind: KindBreakdown[]（kind ごとの byOS / byAsOrg）へ置き換える。summarize() で kind ごとに breakdown() を呼ぶ。
3. dashboard.tsx: 合算の「OS 別」「接続元組織別」テーブルを、3 指標 x 2 軸の 6 テーブル（例:「ページアクセス: OS 別」）へ置き換える。カウンタカードのラベル「訪問」を「ページアクセス」に揃える。
4. test/dashboard.test.ts: kind ごとに OS / as_org が分かれて集計されることを検証するテストを追加（既存の HTTP 経由 + HTML 断片アサーションの方針に沿う）。
5. site/README.md: 合算表示を廃止し per-kind へ置き換えた方針を記載（AC #4）。
6. npm test / npm run typecheck を通す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 単純化の検討どおり SQL の新設は不要だった。breakdown() が既に kind フィルタを持つため、呼び出しを指標ごとに増やすだけで per-kind 集計が得られる。

- src/analytics.ts: Summary の合算 byOS / byAsOrg を perKind: KindBreakdown[]（kind / label / total / byOS / byAsOrg）へ置き換えた。指標の順序と表示名は KIND_LABELS 1 箇所に集約し、Totals は counts: Record<EventKind, number> + uniqueVisitorDays へ整理した。breakdown() の kind 引数も string から EventKind へ絞った。
- src/views/dashboard.tsx: カウンタカードと OS 別 / 接続元組織別テーブルの両方を perKind から描画するようにし、合算の「OS 別」「接続元組織別」テーブルを廃止した（カードの id=count-<kind> は SSE の加算先なので不変）。ラベル「訪問」は「ページアクセス」に統一。
- 国別・参照元別は「どこから来訪したか」の軸で指標別に割っても情報が増えないため合算のまま残した（README に理由を記載）。

検証: site/ で npm test（5 files / 44 tests all pass）と npm run typecheck（エラーなし）。加えて使い捨てテストで /dashboard の実 HTML を描画し、3 指標のカードと 6 テーブル（ページアクセス/ダウンロード/アップデート確認 x OS 別/接続元組織別）に各指標のイベントだけが現れることを目視確認した（確認後に削除）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
analytics ダッシュボードのアクセス集計を visit / download / update_check の 3 指標に分離した。合算の「OS 別」「接続元組織別」テーブルを廃止し、指標 x 軸の 6 テーブルへ置き換え（AC #4 の判断は「置き換える」でユーザー承認済み、site/README.md「ダッシュボードの指標の分け方」に記載）。既存の breakdown() の kind フィルタを流用したため SQL の新設・スキーマ変更は不要。指標の順序と表示名は analytics.ts の KIND_LABELS に集約し、カードと表が同じ定義を参照する。検証は site/ の npm test（44 tests pass、指標ごとに OS / as_org が分かれることを検証する新規テスト 2 本を含む）と npm run typecheck、および実 HTML の目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
