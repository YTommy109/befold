---
id: TASK-73.9
title: check/bookmark という名前のファイル・フォルダをサブコマンド名が奪ってCLIから開けない
status: To Do
assignee: []
created_date: '2026-07-20 13:30'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/CLIArgumentParser.swift:79-81'
parent_task_id: TASK-73
priority: medium
type: bug
ordinal: 56000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIArgumentParser.parse は先頭引数を無条件にサブコマンド名("bookmark"/"check")と照合するため、"check" または "bookmark" という名前の実在するファイル/フォルダを唯一の引数として渡すと、パスとしてではなくサブコマンド呼び出しとして解釈されてしまう。結果として CLICheckCommand.run([]) 等が引数不足のusageエラー(exit 64)を返し、そのファイル/フォルダをCLIから開く手段がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 "check"/"bookmark" という名前のパスをCLI経由で開けること(例: -- によるエスケープ、または実在パスの優先判定)
- [ ] #2 回帰テストを追加する
<!-- AC:END -->
