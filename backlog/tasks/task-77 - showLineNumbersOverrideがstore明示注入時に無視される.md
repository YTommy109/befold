---
id: TASK-77
title: showLineNumbersOverrideがstore明示注入時に無視される
status: To Do
assignee: []
created_date: '2026-07-21 00:52'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowController.init で store: ViewerStore? パラメータに明示的な store を渡した場合、showLineNumbersOverride が適用されない。self.store = store ?? ViewerStore(defaults: defaults, showLineNumbersOverride: showLineNumbersOverride) は store が nil の場合のみ override を反映するため、store と showLineNumbersOverride を両方渡す呼び出しでは override が黙って無視される(コンパイルエラーにならない)。task-73.13 の修正(swift test 527件通過時点)で導入された回帰。参照: code review finding, BefoldApp/befold/App/ViewerWindowController.swift:108
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 store: と showLineNumbersOverride: を両方指定した場合でも showLineNumbersOverride が反映されること
- [ ] #2 回帰テストを追加する
<!-- AC:END -->
