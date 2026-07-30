---
id: TASK-182.6
title: 参照元（referrer）を計測しダッシュボードに集計軸を追加する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-29 14:49'
updated_date: '2026-07-29 23:51'
labels: []
dependencies: []
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: medium
ordinal: 277000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在の events テーブルには参照元のカラムが無く、どの経路から流入したかが分からない。GitHub Pages をリダイレクト専用にする（TASK-182.5）と Pages 経由の流入が発生するため、その数と外部サイト（HN・Reddit・X など）からの流入を把握できるようにする。

計測は 2 系統を 1 本の経路にまとめる方針とする。クエリパラメータ ?ref= を明示的な参照元として最優先で採用し、無い場合は Referer ヘッダのオリジンにフォールバックする。GitHub Pages は静的ホスティングでサーバーサイドリダイレクトができず meta refresh / JS になるため、ブラウザ既定の Referrer-Policy (strict-origin-when-cross-origin) と実装差により Referer は取りこぼしが出る。?ref= はその影響を受けず確実に数えられるため併用が必要。

プライバシーは既存設計（IP はハッシュ化して visitor_day に、UA は要約のみ保存）に合わせ、Referer はフルパスを捨ててオリジンのみ保存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 events テーブルに参照元カラムが追加され、マイグレーションが Atlas 経由で生成・適用される
- [x] #2 ?ref= が付いたリクエストはその値が参照元として記録される
- [x] #3 ?ref= が無い場合は Referer ヘッダのオリジンのみが参照元として記録される（フルパスは保存しない）
- [x] #4 参照元が取得できない直接アクセスでも記録処理が失敗せずイベント自体は残る
- [x] #5 ダッシュボードに参照元別の上位集計が表示される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. src/lib/referrer.ts を新設し resolveReferrer(refParam, refererHeader, selfHost) を実装する。?ref= を最優先（trim・長さ上限でサニタイズ）、無ければ Referer をパースしてオリジンのみ返す。パース不能・空は null。自サイト同一ホストからの Referer は内部遷移なので null にして参照元統計を汚さない。
2. test/referrer.test.ts を先に書く（TDD）。?ref= 優先 / Referer オリジン化 / フルパス破棄 / 不正 URL / 同一ホスト除外 / 両方なし。
3. schema/schema.sql に referrer TEXT を追加し、npm run migrate:diff で Atlas にマイグレーションを生成する。
4. src/schema.ts の eventSchema に referrer を追加。src/events.ts の INSERT 文・bind・組み立てに referrer を通す。
5. src/analytics.ts の BreakdownColumn に 'referrer' を追加し、Summary に byReferrer、summarize() に breakdown(db,'referrer') を追加する。
6. src/views/dashboard.tsx に参照元別の CountTable を追加する。
7. test/schema.test.ts・dashboard.test.ts・public.test.ts を更新。npm test と npm run typecheck を通す。
8. migrate:local で検証後、migrate:remote で本番 D1 に適用し deploy する（デプロイ前にユーザーへ確認）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
src/lib/referrer.ts に resolveReferrer() を新設し、?ref= を最優先・無ければ Referer のオリジンのみ採用・自サイト同一ホストは除外・64 文字上限で実装した。

設計判断: 自サイト内遷移（LP → /download 等）の Referer を記録しない。記録すると自分のオリジンが参照元ランキングの首位を占め統計が無意味になるため。テストで固定している。

?ref= と Referer を併用する理由: GitHub Pages は静的ホスティングでサーバーサイドリダイレクトができず meta refresh / JS になるため、ブラウザ既定の Referrer-Policy (strict-origin-when-cross-origin) と実装差で Referer は取りこぼす。?ref= はその影響を受けない。一方 Referer は ?ref= では測れない外部サイト（HN 等）からの流入を捉えるので、両方を 1 本の解決経路にまとめた。

スコープ追加（ユーザー承認済み）: BefoldKit/AppLinks.swift の homepage を GitHub Pages から https://befold.tommy109.workers.dev/?ref=about へ変更した。About パネル経由の流入を新規流入と切り分けて数えるため。befoldTests/AppLinksTests.swift でホストと ref を固定。

検証: site の vitest 39 件通過（referrer 単体 9・記録経路 4・ダッシュボード集計 1 を新規）、tsc --noEmit クリーン、swift test 783 件通過。本番 D1 へ migrate:remote 適用後（既存 33 行維持・referrer カラム追加を PRAGMA table_info で確認）deploy し、本番へ 4 パターンを実リクエストして D1 の値を確認した: ?ref=verify-param→verify-param / 外部 Referer→https://news.ycombinator.com（パス破棄）/ 自サイト Referer→NULL / 参照元なし→NULL かつイベントは記録。

注意: マイグレーションは必ず deploy より先に当てる。insertEvent は例外を飲むため、カラム未追加のまま新コードが動くと計測が静かに欠落する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
events テーブルに referrer カラムを追加し、?ref= クエリを最優先・無ければ Referer のオリジンのみを参照元として記録するようにした（自サイト内遷移は除外、64 文字上限）。ダッシュボードに参照元別の上位集計を追加し、About パネルのリンクを配布サイトの ?ref=about へ切り替えた。site 39 テスト・swift 783 テスト・tsc がすべて通過。本番 D1 へマイグレーション適用後にデプロイし、?ref= / 外部 Referer / 自サイト Referer / 参照元なしの 4 パターンを実リクエストで投げて D1 の記録値を確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
