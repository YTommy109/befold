---
id: TASK-1.5
title: ViewerWindowController の減量と依存注入（ViewerStore/DirectoryLister 注入、ツールバー・スワイプ抽出）
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-16 03:44'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/213
parent_task_id: TASK-1
priority: medium
ordinal: 11500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #213 から移行。ViewerWindowController（812行、out_degree 46）に7責務が同居。ツールバーとスワイプ検知を独立クラスへ抽出し、ViewerStore と DirectoryLister を init 注入に変え、AppDelegate.shared?.openViewer を注入クロージャ化する。isSourceMode の二重保持とツールバー検索の重複も解消する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツールバーとスワイプ検知が独立クラスに抽出されている
- [ ] #2 ViewerStore と DirectoryLister が init 注入されている
- [ ] #3 AppDelegate.shared?.openViewer が注入クロージャ化されている
- [ ] #4 isSourceMode の二重保持が解消されている
<!-- AC:END -->
