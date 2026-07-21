---
id: TASK-73.9
title: check/bookmark という名前のファイル・フォルダをサブコマンド名が奪ってCLIから開けない
status: Done
assignee:
  - '@claude'
created_date: '2026-07-20 13:30'
updated_date: '2026-07-21 00:22'
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
- [x] #1 "check"/"bookmark" という名前のパスをCLI経由で開けること(例: -- によるエスケープ、または実在パスの優先判定)
- [x] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
swift-argument-parserへの移行(task-76)の一部として、-- ターミネータで実在パスをサブコマンド名より優先解釈できるようにする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
task-76(swift-argument-parserへの移行)で解決。BefoldRootCommandは check/bookmark を購読済みサブコマンドとして扱うため、名前が衝突する実在パスは befold -- check のように -- でエスケープすることでパスとして開ける(BefoldRootCommandTests.dashDashEscapesSubcommandLikePathNamesで検証)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
swift-argument-parser移行(task-76)で -- エスケープを導入し、check/bookmarkという名前の実在パスも befold -- check のようにサブコマンドと区別して開けるようにした。
<!-- SECTION:FINAL_SUMMARY:END -->
