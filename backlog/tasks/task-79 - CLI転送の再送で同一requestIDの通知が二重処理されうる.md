---
id: TASK-79
title: CLI転送の再送で同一requestIDの通知が二重処理されうる
status: To Do
assignee: []
created_date: '2026-07-21 00:52'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 64000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIInstanceRouter.forward() はACK未受信時に同じ requestID で通知を再送するが、先の試行を取り消さない。受信側の観測が最初の試行のackTimeout(0.5秒)を過ぎた直後に間に合って登録された場合、最初の通知と再送された通知の両方が届き得る。handleCLIOpenRequest はrequestID単位の重複排除を行っていないため、openPaths/toggleが二重実行される(同じファイルの二重オープン、隠しファイル表示の二重トグル等)可能性がある。参照: code review finding(PLAUSIBLE), BefoldApp/befold/App/CLIInstanceRouter.swift:50
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一requestIDの通知が複数回受信されても、受信側でopenPaths等の処理が一度しか実行されないこと
- [ ] #2 回帰テストを追加する(実際のDistributedNotificationCenterに依存しない形で再現可能なテスト)
<!-- AC:END -->
