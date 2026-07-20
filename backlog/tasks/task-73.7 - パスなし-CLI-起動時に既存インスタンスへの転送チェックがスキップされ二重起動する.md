---
id: TASK-73.7
title: パスなし CLI 起動時に既存インスタンスへの転送チェックがスキップされ二重起動する
status: To Do
assignee: []
created_date: '2026-07-20 13:30'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/AppDelegate.swift:101'
parent_task_id: TASK-73
priority: high
type: bug
ordinal: 54000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppDelegate.main() の CLIInstanceRouter.runningInstance() 呼び出しは `!paths.isEmpty` でガードされている。そのため befold が既に起動中でも、パス引数なしの `befold` や `befold --hidden-files` 単体実行は転送チェックを完全にスキップし、常に新しい NSApplication/AppDelegate インスタンスを生成してしまう。SessionStore/BookmarkStore を二重に書き込むプロセスが並立するリスクがある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パス引数なしの CLI 起動でも、既に起動中のインスタンスがあればそちらへ処理を委譲(アクティブ化やオプション適用)し、二重プロセスを生成しないこと
<!-- AC:END -->
