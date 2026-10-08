---
id: TASK-688
title: テスト巨大ファイル（site/test と viewer-test の 1000 行超）を describe 単位で分割する
status: To Do
assignee: []
created_date: '2026-10-08 09:52'
labels:
  - lint
dependencies:
  - TASK-684
priority: low
ordinal: 877000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-684 のテスト上限 1000 行の除外を外す。対象: site/test/analytics.test.ts(1693) public.test.ts(1452) dashboard.test.ts(1342)、BefoldApp/viewer-test/viewer-main.test.ts(1574) viewer.test.ts(1551)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 除外 override を外しても npm run lint が両面で通る
<!-- AC:END -->
