---
id: TASK-73.6
title: 既に起動中のインスタンスへの CLI 転送がオブザーバ未登録で通知をロストする
status: To Do
assignee: []
created_date: '2026-07-20 13:29'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/CLIInstanceRouter.swift:22'
  - 'AppDelegate.swift:100-124'
parent_task_id: TASK-73
priority: high
type: bug
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIInstanceRouter.forward() は DistributedNotificationCenter へ deliverImmediately:true で通知を送りっぱなしにし、確認応答なしで exit(0) する。転送先の既存インスタンスは applicationWillFinishLaunching でオブザーバを登録するため、起動直後で NSRunningApplication には見えるがまだオブザーバ登録前のタイミングで forward() が呼ばれると、通知は誰にも受信されずロストする。CLI プロセスは exit(0) するためユーザーには成功したように見えるが、実際にはファイルが開かれない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 起動直後(オブザーバ未登録)のインスタンスへ forward した open リクエストが確実に届くこと、または届かない場合に CLI 側がエラー/リトライで検知できること
- [ ] #2 再現条件（起動直後の狭いタイミング）を再現するテストまたは検証手順が用意されていること
<!-- AC:END -->
