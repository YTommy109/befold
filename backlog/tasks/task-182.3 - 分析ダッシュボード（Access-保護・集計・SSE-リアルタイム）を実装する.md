---
id: TASK-182.3
title: 分析ダッシュボード（Access 保護・集計・SSE リアルタイム）を実装する
status: To Do
assignee: []
created_date: '2026-07-28 13:35'
labels: []
dependencies: []
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: high
ordinal: 260000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GET /dashboard を Cloudflare Access で所有者のみに保護し、日別 DL・バージョン別内訳・国別・OS 別・update_check 数を集計して htmx で描画する。GET /dashboard/stream で D1 ポーリング型 SSE（2〜3 秒間隔で id>lastSeenId の新着を push）を実装し、htmx SSE 拡張でカウンタと最新イベント一覧を更新する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /dashboard が Cloudflare Access で所有者のみ閲覧できる
- [ ] #2 集計（日別/バージョン別/国別/OS 別/update_check）が表示される
- [ ] #3 /dashboard/stream の SSE で新着イベントがリアルタイムに反映される
<!-- AC:END -->
