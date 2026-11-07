---
id: TASK-920
title: サイドバーの split view の組み立てを文書タブと空タブで共有する
status: To Do
assignee: []
created_date: '2026-11-07T08:35:00Z'
labels:
  - refactor
  - sidebar
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
  - BefoldApp/befold/App/ViewerWindowAssembler.swift
priority: low
type: task
ordinal: 886000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。`BlankTabWindowController.makeContent` は `ViewerWindowAssembler.makeSplitViewController` の配線（`onCollapsedChange` と `tableFocuser` の 2 つのコールバック）を書き写している。TASK-910 の Notes は「組み立ての重複（split view の配線）は Low のため残した」と記録しているが、.claude/CLAUDE.md の完了基準は「タスク中に発見したリファクタリング課題は「次回触るときに」と後回しにせず、同じタスク内で完了する」と定めている。片方だけを直すと、開閉の記録やフォーカスの後始末（TASK-563）が空タブだけずれる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 開閉の記録とフォーカスの配線の定義が 1 箇所になっている
- [ ] #2 文書タブ・空タブ・スライド窓の開閉の動作が変わらず、既存のテストが通る
<!-- AC:END -->
