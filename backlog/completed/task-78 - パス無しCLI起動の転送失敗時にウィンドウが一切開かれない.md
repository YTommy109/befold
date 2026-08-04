---
id: TASK-78
title: パス無しCLI起動の転送失敗時にウィンドウが一切開かれない
status: Done
assignee: []
created_date: '2026-07-21 00:52'
updated_date: '2026-07-21 01:44'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 63000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
task-73.6/73.7の修正により、AppDelegate.launch はパスの有無に関わらず既存インスタンスへの forward() を試み、ACKタイムアウトで失敗すると新規インスタンスへフォールバックせずそのまま stderr へエラーを出し exit(1) する。既存インスタンスが起動途中(プロセスは存在するがDistributedNotificationCenterオブザーバ未登録)で forward の再試行予算(3回×0.5秒)を超えるレースが発生すると、befold --hidden-files のようなパス無し起動が『ウィンドウが一切開かれないまま失敗』となる。旧実装ではパス無し起動は転送を試みず常に自分自身のセッションを復元しウィンドウを開いていたため、これは新たに導入された退行。参照: code review finding, BefoldApp/befold/App/AppDelegate.swift:77, BefoldApp/befold/App/CLIInstanceRouter.swift
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 既存インスタンスへの転送に失敗した場合、ユーザーには何らかのウィンドウが開かれる(新規インスタンスとしてセッション復元/オプション適用にフォールバックする、または他の形でユーザーの意図が満たされる)こと
- [x] #2 task-73.7で修正した『パス無し起動で二重起動する』問題を再発させないこと
- [x] #3 回帰テストまたは検証手順を追加する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化を検討: 分岐(existing/forward成否/paths有無)を launch() 内に増やす代わりに、副作用の無い純粋関数 decideLaunchAction(paths:runningInstance:forwardSucceeded:) へ切り出した。これにより exit()/NSApplication.run() に依存せずユニットテストで分岐を検証できる。パス指定ありの転送失敗時の挙動(exitWithForwardError)は本タスクのスコープ外として変更していない(task-73.6以前から同じ挙動で、今回のタイトルは『パス無し起動』の回帰に限定されている)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppDelegate.launch() の転送失敗時フォールバック欠如(task-78)を修正。パスの有無・転送成否・既存インスタンスの有無から行動を決める純粋関数 decideLaunchAction を切り出し、パス無し起動で転送に失敗した場合は launchAsNewInstance(旧実装同様に自身のセッションを復元してウィンドウを開く)にフォールバックするようにした。パス指定ありの転送失敗は従来通りエラー終了(task-73.7の二重起動修正を維持)。AppDelegateLaunchTests.swift に4件の回帰テストを追加、swift test --skip Integration --skip FileWatcherTests で533件全てパス。
<!-- SECTION:FINAL_SUMMARY:END -->
