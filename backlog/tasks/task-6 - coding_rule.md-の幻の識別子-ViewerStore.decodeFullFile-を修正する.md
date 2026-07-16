---
id: TASK-6
title: coding_rule.md の幻の識別子 ViewerStore.decodeFullFile を修正する
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/208
ordinal: 14000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #208 から移行。docs/dev/coding_rule.md:233 の単一情報源テーブルに実在しない ViewerStore.decodeFullFile を委譲元として記載。実際の経路（DefaultFileReader.readString と LineChunkReader）に修正する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 該当行が実在の識別子を参照している
<!-- AC:END -->
