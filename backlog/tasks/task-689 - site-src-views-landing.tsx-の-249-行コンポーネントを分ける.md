---
id: TASK-689
title: site/src/views/landing.tsx の 249 行コンポーネントを分ける
status: Done
assignee: []
created_date: '2026-10-08 09:52'
updated_date: '2026-10-08 10:48'
labels:
  - lint
  - site
dependencies:
  - TASK-684
priority: low
ordinal: 878000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-684 の max-lines-per-function(150) の除外を外す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 site/.oxlintrc.json の landing.tsx 除外を外しても npm run lint が通る
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
landing.tsx の Landing を Hero / Audiences / Screenshots / FeatureSection / Requirements / Install のセクション部品に分け、site/.oxlintrc.json の max-lines-per-function 除外を撤去。lint・typecheck・format:check・npm test(440) 通過。
<!-- SECTION:FINAL_SUMMARY:END -->
