---
id: TASK-182.5
title: 配布参照を新 URL へ更新し docs/ の LP を縮退する
status: To Do
assignee: []
created_date: '2026-07-28 13:36'
updated_date: '2026-07-29 14:49'
labels: []
dependencies:
  - TASK-182.6
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: low
ordinal: 262000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
README や関連ドキュメントの配布 URL を新 Worker の URL に更新する。Worker の安定稼働を確認した後、docs/ の LP 部分（index.html 等）を開発ドキュメント専用へ縮退する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 README 等の配布リンクが新 Worker URL を指す
- [ ] #2 docs/ の LP 部分が縮退され役割が site/ へ移る
<!-- AC:END -->
