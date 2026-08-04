---
id: TASK-73.7
title: パスなし CLI 起動時に既存インスタンスへの転送チェックがスキップされ二重起動する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-20 13:30'
updated_date: '2026-07-20 23:53'
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
- [x] #1 パス引数なしの CLI 起動でも、既に起動中のインスタンスがあればそちらへ処理を委譲(アクティブ化やオプション適用)し、二重プロセスを生成しないこと
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
AppDelegate.launch()の !paths.isEmpty ガードを削除し、パスの有無に関わらず既存インスタンスがあれば常に forward() へ処理を委譲する(空パスの場合は既存インスタンスをアクティブ化するのみになる)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AppDelegate.launch() の 'if !paths.isEmpty, let running = ...' から !paths.isEmpty を削除。これによりパス無しCLI起動(befold単体・オプションのみ)でも既存インスタンスが動いていれば必ずforward()で委譲し、新規NSApplicationインスタンスを生成しなくなる。launch()はexit()を呼ぶため単体テスト不可(既存コードも同様に未テスト)、swift buildとswift test 525件全パスで回帰なしを確認。手動検証手順: befold起動中に別ターミナルから 'befold' を引数無しで実行し、新規ウィンドウ/プロセスが生成されず既存ウィンドウがアクティブ化されることを確認する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppDelegate.launch()のrunningInstance()呼び出しガードから!paths.isEmptyを除去し、パスなしCLI起動でも既存インスタンスへ処理を委譲するようにした。二重プロセス生成を防止する。
<!-- SECTION:FINAL_SUMMARY:END -->
