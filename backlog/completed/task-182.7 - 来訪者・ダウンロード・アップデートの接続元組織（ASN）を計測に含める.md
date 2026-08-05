---
id: TASK-182.7
title: 来訪者・ダウンロード・アップデートの接続元組織（ASN）を計測に含める
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-30 02:03'
updated_date: '2026-07-30 02:26'
labels: []
dependencies: []
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: low
ordinal: 281000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
どの組織・ネットワークから来訪・ダウンロード・アップデート確認が行われているかが分からない。現在の集計軸は国・OS・バージョン・参照元のみで、参照元は「どのサイト経由か」を表すだけで来訪者自身の所属は表さない。

実現手段は Cloudflare Workers の request.cf にある asn（AS 番号）と asOrganization（その AS の保有組織名、例: Google Cloud）。全プランで利用可能で、追加のサブリクエストもコストも発生しない。visit / download / update_check のいずれも Worker へのリクエストとして届くため、同じ経路で 3 種すべてを取得できる（Sparkle のアップデート確認もユーザー端末から届く）。

【用語の確認が必要な点】ここでの「ドメイン」を AS 組織名と解釈している。より厳密に来訪者のドメイン名（例: acme.co.jp）を得るには IP の逆引き（PTR）が必要で、Workers からは 1.1.1.1 への DNS-over-HTTPS で実現できるが、イベントごとにサブリクエストが増え、かつ企業ネットワークでは端末名を含む識別性の高い文字列（例: pc-tanaka.corp.acme.co.jp）が返るためプライバシー上の影響が大きい。着手時にどちらを採るか確認する。逆引きを採る場合は完全な FQDN ではなく登録可能ドメイン（eTLD+1）だけを保存すること。

【プライバシー方針との整合】既存設計は生 IP を保存せず visitor_day にハッシュ化し、UA も要約のみ保存、Referer はオリジンのみという方針。AS 組織名は一般消費者回線では ISP 名（NTT / KDDI 等）に留まる粗い粒度だが、企業・クラウドからの接続は識別されうる。この粒度が方針と整合するかを着手時に判断する。

【実装上の注意】既存コードは country を CF-IPCountry ヘッダから取得しているが、asn / asOrganization に相当するヘッダは無く request.cf（Hono では c.req.raw.cf）を参照する必要がある。cf は Cloudflare ダッシュボードや Playground では利用できず、ローカル / テスト環境ではモックまたは undefined になるため、未取得時に記録処理が壊れない実装とテストが必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 events テーブルに接続元組織を保存するカラムが追加され、マイグレーションが Atlas 経由で生成・適用される
- [x] #2 visit / download / update_check の 3 種すべてで接続元組織が記録される
- [x] #3 request.cf が利用できない環境（ローカル・テスト）でも記録処理が失敗せずイベント自体は残る
- [x] #4 ダッシュボードに接続元組織別の上位集計が表示される
- [x] #5 保存する情報の粒度がプライバシー方針（生 IP を保存しない・UA は要約のみ）と整合していることが README に記載される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. schema/schema.sql に as_org カラムを追加し、atlas migrate diff でマイグレーション生成、wrangler d1 migrations apply --local で適用
2. src/schema.ts の eventSchema に asOrg を追加
3. src/events.ts の insertEvent で c.req.raw.cf?.asOrganization ?? null を取得し記録（cf 未定義でも例外にならない形）。INSERT_SQL に as_org を追加
4. src/analytics.ts の BreakdownColumn に 'as_org' を追加、Summary/summarize に byAsOrg を追加
5. src/views/dashboard.tsx に「接続元組織別」の CountTable を追加
6. test/public.test.ts の call() ヘルパーで cf を注入できるようにし、asOrganization ありなし双方のケース（cf 未定義でもイベントが記録されること含む）をテスト
7. README.md に asOrganization の粒度がプライバシー方針と整合する旨を追記
8. npm test / npm run typecheck で検証
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: schema/schema.sql に as_org 列を追加し atlas migrate diff で migrations/20260730022424_add_as_org.sql を生成、migrate:local で適用。events.ts で c.req.raw.cf?.asOrganization ?? null を記録（cf 未定義でもイベントは記録継続）。analytics.ts/dashboard.tsx に接続元組織別の上位集計を追加。README に粒度とプライバシー方針の整合性を明記。検証: npm test (42 passed, 5 files) / npm run typecheck 両方成功。事前確認: 「asOrganization のみ採用」「既存プライバシー方針と整合する」の2点をユーザーに確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
visitor_day 由来の visit/download/update_check 全イベントに request.cf.asOrganization を as_org カラムとして記録し、ダッシュボードに接続元組織別の上位集計を追加した。request.cf が無い環境でもイベント記録は継続する。README にプライバシー方針との整合性を追記。npm test（42件）・npm run typecheck で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
