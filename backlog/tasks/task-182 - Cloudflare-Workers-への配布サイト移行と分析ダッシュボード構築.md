---
id: TASK-182
title: Cloudflare Workers への配布サイト移行と分析ダッシュボード構築
status: To Do
assignee: []
created_date: '2026-07-28 13:34'
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
- [ ] #1 配布 LP・ダウンロードリダイレクト・appcast プロキシ・分析ダッシュボードが Cloudflare Worker 上で稼働する
- [ ] #2 ダッシュボードは Cloudflare Access で所有者のみ閲覧でき、SSE でリアルタイム更新される
- [ ] #3 既存の Sparkle アップデート（旧 appcast）が後方互換で維持される
<!-- AC:END -->
