---
id: TASK-78
title: パス無しCLI起動の転送失敗時にウィンドウが一切開かれない
status: To Do
assignee: []
created_date: '2026-07-21 00:52'
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
- [ ] #1 既存インスタンスへの転送に失敗した場合、ユーザーには何らかのウィンドウが開かれる(新規インスタンスとしてセッション復元/オプション適用にフォールバックする、または他の形でユーザーの意図が満たされる)こと
- [ ] #2 task-73.7で修正した『パス無し起動で二重起動する』問題を再発させないこと
- [ ] #3 回帰テストまたは検証手順を追加する
<!-- AC:END -->
