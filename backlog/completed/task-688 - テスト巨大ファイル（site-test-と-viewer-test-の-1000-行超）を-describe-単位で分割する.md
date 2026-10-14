---
id: TASK-688
title: テスト巨大ファイル（site/test と viewer-test の 1000 行超）を describe 単位で分割する
status: Done
assignee: []
created_date: '2026-10-08 09:52'
updated_date: '2026-10-08 10:36'
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
- [x] #1 除外 override を外しても npm run lint が両面で通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
5 ファイルを describe 単位で 2〜3 本ずつに分割（site: analytics 3本/public 2本/dashboard 2本 + 各 helpers、viewer-test: viewer-main 2本/viewer 2本）。テスト数は分割前後で一致（89/129/103/103/249）。TASK-684 の max-lines 除外 override を両 .oxlintrc.json から撤去し、npm run lint・typecheck・format:check・全テストが両面で通ることを確認。
<!-- SECTION:NOTES:END -->
