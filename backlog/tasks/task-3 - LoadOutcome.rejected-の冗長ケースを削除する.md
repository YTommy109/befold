---
id: TASK-3
title: LoadOutcome.rejected の冗長ケースを削除する
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/205
ordinal: 11000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #205 から移行。LoadOutcome の .rejected(RejectReason) は .full(LoadedContent(rejectReason:)) と等価で冗長。apply() で同じ 6 フィールドを設定しており、.rejected は content="" の特殊化に過ぎない。生成箇所は computeLoad の 1 箇所のみ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .rejected ケースが削除され .full で統一されている
<!-- AC:END -->
