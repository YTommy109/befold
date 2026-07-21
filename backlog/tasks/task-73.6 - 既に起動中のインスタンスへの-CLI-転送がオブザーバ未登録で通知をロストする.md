---
id: TASK-73.6
title: 既に起動中のインスタンスへの CLI 転送がオブザーバ未登録で通知をロストする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-20 13:29'
updated_date: '2026-07-20 23:51'
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
- [x] #1 起動直後(オブザーバ未登録)のインスタンスへ forward した open リクエストが確実に届くこと、または届かない場合に CLI 側がエラー/リトライで検知できること
- [x] #2 再現条件（起動直後の狭いタイミング）を再現するテストまたは検証手順が用意されていること
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIInstanceRouter.forward()にrequestID+ACK待ち・再送(post/waitForAckを注入可能に)を実装し、DistributedNotificationCenter依存を差し替え可能にする\n2. AppDelegate.handleCLIOpenRequestで受信直後にACKを送り返す\n3. launch()でforward()の戻り値がfalseならエラーメッセージをstderrへ出しexit(1)する(既存インスタンスと二重に起動しない)\n4. post/waitForAckを注入したユニットテストでリトライ・ACKロジックを検証する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLIInstanceRouter.forward()にrequestID発行+ACK待ち(post/waitForAckを注入可能)を実装。ACK未受信ならmaxForwardAttempts(3回)まで同じrequestIDで再送し、それでも届かなければfalseを返す。AppDelegate.handleCLIOpenRequestは受信直後にsendAck(requestID:)でACKを送り返す。launch()はforward()==falseの場合、既存インスタンスを起動せずstderrへエラーを出してexit(1)する(二重起動を避ける)。CLIInstanceRouterTests.swiftでpost/waitForAckを注入し、初回ACK成功・再送後ACK成功・maxAttempts超過でfalseの3パターンをDistributedNotificationCenterなしで決定的に検証。swift test 529件全パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
既存インスタンスへのCLI転送にrequestID+ACK方式を導入し、通知ロスト(起動直後のオブザーバ未登録)を検知・再送で救済するようにした。ACKが最終的に得られない場合は新規インスタンスを起動せずエラー終了する(二重起動防止)。post/waitForAckを注入可能にしてタイミングを決定的に再現するユニットテストを追加。
<!-- SECTION:FINAL_SUMMARY:END -->
