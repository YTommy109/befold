---
id: TASK-86
title: CLIInstanceRouter.forward()がACK消失+観測不能な失敗を宛先生存だけで成功扱いし、リクエスト未処理が握りつぶされる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 07:21'
updated_date: '2026-07-21 08:22'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/CLIInstanceRouter.swift
priority: high
type: bug
ordinal: 71000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
forward() は maxAttempts 回 ACK を待っても届かない場合、宛先プロセスが生存していれば(!isTerminated)「ACK消失だが処理済み」とみなし成功として扱う(TASK-81 で導入した設計)。しかし「宛先が生存している」ことは「リクエストを実際に処理した」ことの証明にはならない。
具体的には次の2ケースで、リクエストが実際には処理されていないのに forward() が true を返し、CLI は成功終了(ファイルは開かれない)する:
1. 起動直後でまだ DistributedNotificationCenter オブザーバの登録(init())が完了していないインスタンスへ転送するタイミング(TASK-85 でオブザーバ登録を init() へ前倒ししたが、プロセス生成から init() 実行までの間の窓は原理的に残る)
2. 宛先インスタンスが生存はしているが RunLoop がハングしていて通知を処理できない場合
コードコメント自身が「ほぼ確実に配送されている」という推定に基づく設計であることを認めており、再送・確認応答つきの配送保証やタイムアウト付きリトライキューは持たない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 宛先プロセスの生存のみをもってACK消失時の成功と判定する現行ロジックの妥当性(TASK-81/TASK-85との関係)を再検討し、方針(許容/改善)を明記する
- [ ] #2 改善する場合、宛先がリクエストを実際に処理したことを示すより強いシグナル、またはユーザーに通知可能な形での失敗検出手段を提供する
- [x] #3 起動直後のオブザーバ未登録タイミングでの転送、および宛先RunLoopハング時の挙動を再現するテストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現状のforward()設計(宛先生存のみで成功扱い)は、TASK-81でATask-73.6/85のレース対応と合わせて意図的に採用した簡素な設計であり、これ以上ズレを詰めるには同期的なIPC(XPC/ソケットハンドシェイク等)への作り直しが必要で、残存する2つのシナリオ(起動直後の極小レース窓、宛先RunLoopハング)に対して割に合わない。ユーザー承認により方針は「許容」で確定。
2. forward()のdocコメントに、起動直後race窓とRunLoopハングの2シナリオを名指しし、それらがforward()からは区別不能であり意図的に許容していることを明記する。
3. 既存テストreturnsTrueWhenAckLostButDestinationAlive(CLIInstanceRouterTests.swift:65)は、forward()の視点からは両シナリオを区別できないため、既にこの2シナリオの現状挙動を規定するテストであることを、テストのdocコメント/表示名で明示する(新規の重複テストは追加しない)。
4. AC#1を「許容」の判断を明記して満たし、AC#2は「改善しない」判断であるため本文中でその判断根拠を明記した上でスコープ外とする、AC#3は既存テストの明示化で満たす。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ユーザーに方針確認(現状design許容 vs レース窓のさらなる縮小)を実施し、「現状design を許容し、テストで明文化のみ」を選択いただいた。

検証: swift test --filter CLIInstanceRouterTests で5件green(returnsTrueWhenAckLostButDestinationAliveが起動直後オブザーバ未登録/宛先RunLoopハングの両シナリオをforward()視点で規定するテストであることをdocコメントで明示)。AC#2は、ユーザー承認により「現状designを許容、改善は実施しない」と決定したため意図的に未実施・未チェックとする。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
forward()のdocコメントに、宛先生存=成功とみなす現行設計が起動直後のオブザーバ未登録レース窓・宛先RunLoopハングの2シナリオを区別できない既知の限界であることを明記(task-86)。ユーザーに方針確認し、同期IPCへの作り直しは残存レース窓の狭さに対して過剰投資と判断、現状design を許容する方針で確定。既存テストreturnsTrueWhenAckLostButDestinationAlive(CLIInstanceRouterTests.swift)がこの2シナリオを同一挙動として規定していることをdocコメントで明示。swift test --filter CLIInstanceRouterTestsで5件green。AC#2(改善の実装)はユーザー承認済みの「許容」方針によりスコープ外。
<!-- SECTION:FINAL_SUMMARY:END -->
