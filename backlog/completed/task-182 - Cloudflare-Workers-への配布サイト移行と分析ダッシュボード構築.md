---
id: TASK-182
title: Cloudflare Workers への配布サイト移行と分析ダッシュボード構築
status: Done
assignee: []
created_date: '2026-07-28 13:34'
updated_date: '2026-07-30 00:01'
labels: []
dependencies: []
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
priority: high
ordinal: 257000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
配布経路を GitHub Pages から Cloudflare Workers (Hono/TypeScript) へ移し、ダウンロード数・アップデートチェック・ビジター数をリアルタイムに把握できるようにする。配布ページは公開、分析ダッシュボードは所有者のみ Cloudflare Access で閲覧可能とする。DMG 実体と GitHub の署名・公証フローは変更しない。詳細は設計 spec を参照。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 配布 LP・ダウンロードリダイレクト・appcast プロキシ・分析ダッシュボードが Cloudflare Worker 上で稼働する
- [x] #2 ダッシュボードは Worker 側の Basic 認証で所有者のみ閲覧でき、SSE でリアルタイム更新される
- [x] #3 既存の Sparkle アップデート（旧 appcast）が後方互換で維持される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
受入条件 #2 の認可方式を Cloudflare Access から Basic 認証へ改めた。独自ドメインを取得せず *.workers.dev で公開する方針が確定し、Access のアプリケーションは自アカウントのゾーンのホスト名にしか設定できず Cloudflare 所有ドメインである workers.dev を保護対象にできないため（TASK-182.3 の方針変更 2026-07-29）。当初の文言が実装と乖離したままだったので実態に合わせた。

受入条件の検証（2026-07-30、本番 https://befold.tommy109.workers.dev）:
#1 / 200・/download 302（v1.10.0 の DMG へ）・/appcast.xml 200・/appcast-develop.xml 200・/dashboard 401 と全ルートが稼働。
#2 認証情報なし・誤った認証情報・SSE（/dashboard/stream）のいずれも 401。正しい認証情報での 200 到達はユーザーがブラウザで確認済み（パスワードはシークレットのため CLI 側からは検証不可）。SSE のリアルタイム push は site の vitest で担保。
#3 リリース済みバイナリが参照する GitHub の appcast（releases/download/appcast/appcast.xml）が 200 で生存。Worker 経由の /appcast.xml と sha256 先頭 16 桁が一致（14db27ddc2b6f026）し、プロキシが内容を改変していないことを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布経路を GitHub Pages から Cloudflare Worker（Hono/TypeScript）へ移行し、配布 LP・DL リダイレクト・appcast プロキシ・分析ダッシュボード（Basic 認証・SSE）を稼働させた。参照元計測を追加し、GitHub Pages はリダイレクト専用に縮退して二重管理と計測漏れを解消した。公開 URL は https://befold.tommy109.workers.dev。認可は workers.dev では Cloudflare Access が使えないため Worker 側の Basic 認証を採用した。本番の全ルート疎通・401 挙動・GitHub appcast との byte 一致で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
