---
id: TASK-485.25
title: 文書内ジャンプのショートカット（cmd+shift+F）を紹介サイトの表に載せる
status: To Do
assignee: []
created_date: '2026-08-23 16:35'
updated_date: '2026-09-25 08:34'
labels:
  - jump
dependencies:
  - TASK-485.16
parent_task_id: TASK-485
ordinal: 799000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
キー等価の割り当て自体は TASK-485.28 で行った（cmd+shift+F。ジャンプ 3 種が排他なので 1 キー）。紹介サイトのショートカット表（site/src/lib/shortcuts.ts）は開発中機能のゲートを認識しないため、ゲート撤去（TASK-485.16）まで反映を待つ。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 site/src/lib/shortcuts.ts と紹介サイトのショートカット表に反映されている
<!-- AC:END -->
