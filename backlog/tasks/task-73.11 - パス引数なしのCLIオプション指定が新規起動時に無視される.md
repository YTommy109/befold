---
id: TASK-73.11
title: パス引数なしのCLIオプション指定が新規起動時に無視される
status: To Do
assignee: []
created_date: '2026-07-20 13:30'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/AppDelegate.swift:142'
parent_task_id: TASK-73
priority: medium
type: bug
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppDelegate.applicationDidFinishLaunching は initialPaths が空の場合 restoreLastSession() のみを呼び、initialOptions を一切参照しない。既存インスタンスがなく新規起動する場合、`befold --hidden-files` のようなパスなし・オプションのみのCLI起動はパース自体は成功するにもかかわらず、指定したオプションが何にも適用されない無言の無効化(no-op)になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 パス引数なしでもCLIオプション(隠しファイル表示・並び順・行番号・ソース/プレビューモード等)がセッション復元後のウィンドウ、または今後開くウィンドウに適用されること
- [ ] #2 回帰テストを追加する
<!-- AC:END -->
