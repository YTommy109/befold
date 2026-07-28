---
id: TASK-182.4
title: アプリの Sparkle フィード URL を新 Worker へ切り替える
status: To Do
assignee: []
created_date: '2026-07-28 13:35'
labels: []
dependencies:
  - TASK-182.2
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: medium
ordinal: 261000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/Updates/UpdateChannel.swift の feedURLString（stable/develop 両方）を新 Worker の appcast URL に変更する。旧 GitHub appcast 固定タグは既存ユーザーのため残す（後方互換）。この変更を含むアプリをリリースすると既存ユーザーは次回チェックで新フィードへ移行する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 UpdateChannel.swift の stable/develop フィード URL が新 Worker の appcast URL を指す
- [ ] #2 旧 GitHub appcast 固定タグは維持され既存ユーザーが壊れない
- [ ] #3 新フィード経由でアップデートチェックが成功する（手動確認）
<!-- AC:END -->
