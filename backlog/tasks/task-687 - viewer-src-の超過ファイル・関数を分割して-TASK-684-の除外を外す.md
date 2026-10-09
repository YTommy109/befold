---
id: TASK-687
title: viewer-src の超過ファイル・関数を分割して TASK-684 の除外を外す
status: Done
assignee: []
created_date: '2026-10-08 09:52'
updated_date: '2026-10-08 10:31'
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
- [x] #1 BefoldApp/.oxlintrc.json の viewer-src 除外 override を外しても npm run lint が通る
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
find/jump/jump-providers/diff-html/render を分割し、TASK-684 の viewer-src 除外 override 3 件を撤去。lint・typecheck・jest 693・循環検査・バンドル再生成を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
