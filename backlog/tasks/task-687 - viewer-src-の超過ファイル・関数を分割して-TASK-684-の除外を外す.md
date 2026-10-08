---
id: TASK-687
title: viewer-src の超過ファイル・関数を分割して TASK-684 の除外を外す
status: To Do
assignee: []
created_date: '2026-10-08 09:52'
labels:
  - lint
  - viewer
dependencies:
  - TASK-684
priority: low
ordinal: 876000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-684 で入れた size 上限の override 除外を外す。対象: diff-html.ts(578) find.ts(587・_createFindController 389 行) jump.ts(448・関数 248 行) jump-providers.ts(454) render.ts(complexity 30 / max-depth 5)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 BefoldApp/.oxlintrc.json の viewer-src 除外 override を外しても npm run lint が通る
<!-- AC:END -->
