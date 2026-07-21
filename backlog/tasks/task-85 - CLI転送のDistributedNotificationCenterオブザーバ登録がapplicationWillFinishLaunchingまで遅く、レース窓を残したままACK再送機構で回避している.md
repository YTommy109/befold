---
id: TASK-85
title: >-
  CLI転送のDistributedNotificationCenterオブザーバ登録がapplicationWillFinishLaunchingまで遅く、レース窓を残したままACK再送機構で回避している
status: Done
assignee: []
created_date: '2026-07-21 05:46'
updated_date: '2026-07-21 06:06'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/AppDelegate.swift
priority: low
type: enhancement
ordinal: 70000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI転送のオブザーバ登録は AppDelegate.applicationWillFinishLaunching 内でのみ行われる。これは NSApplication.run() が動き出した後に発火するため、task-73.6 で追加された ACK + リトライ + 重複排除の仕組み（CLIInstanceRouter.forward の requestID/ack ループ、CLIRequestDeduplicator）は、根本のレース窓を閉じるのではなく、その窓を回避するために組まれている。
オブザーバ登録を AppDelegate.init() （NSApplication.run() 呼び出し前に同期実行される）など、より早いタイミングに移せれば、task-73.6 が対処しようとしたレース窓自体を縮小・解消できる可能性がある。ただしこれは verify エージェントの判定が CONFIRMED ではなく PLAUSIBLE（AppDelegate.init() のタイミングでオブザーバ登録が実際に安全に行えるかは未検証）であるため、着手前に現状のレース発生条件と init() 移設の安全性を調査すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI転送オブザーバの登録タイミングと起動シーケンス（init/applicationWillFinishLaunching/NSApplication.run）の関係を調査し、より早い登録が可能かどうかの結論を記録する
- [x] #2 登録タイミングを早められる場合は移設し、既存の ACK+リトライ+重複排除機構が単純化できるか（あるいは残す必要がある理由）を明記する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 起動シーケンスを調査: launch() の .launchAsNewInstance 分岐で AppDelegate(initialPaths:initialOptions:) を生成した直後に app.delegate=delegate; AppDelegate.shared=delegate; app.run() を呼ぶ。NSRunningApplicationは launch services 登録済プロセスとして、app.run() 開始前・applicationWillFinishLaunching発火前から他プロセスから『起動中』に見えうる。DistributedNotificationCenterへのaddObserverはランループ稼働を前提としない(登録自体は同期APIで、配送はランループ稼働後になるだけ)ため、init()末尾(super.init()直後)で登録しても安全。\n2. 結論: 登録をinit()へ前倒し可能(CONFIRMED)。windowManager/sessionRestorer/cliRequestDeduplicatorはinit()内で他のプロパティ代入より前に生成済みのため、handleCLIOpenRequestが早期発火しても依存関係の不備は無い。\n3. ACK+リトライ+重複排除機構は単純化できない: (a)ACK消失(task-81)はforward request到達後の応答側の消失であり登録タイミングとは無関係。(b) DistributedNotificationCenter自体がベストエフォート配送でありinit()時登録後もレース窓が完全にゼロにはならない(縮小するのみ)。よって既存のretry/dedup機構はそのまま維持する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査結果(CONFIRMED): observer登録をapplicationWillFinishLaunchingからAppDelegate.init()(super.init()直後)へ移設。既存のACK+リトライ+重複排除機構(CLIInstanceRouter.forward/CLIRequestDeduplicator)はレース窓を縮小するだけでは根絶できない別要因(ACK自体の消失、DNCのベストエフォート特性)に対応するため維持が必要と判断し、変更しない。swift build / swift test(543件)全てgreen。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
起動シーケンスを調査し、DistributedNotificationCenterのaddObserverはランループ稼働を前提としないため、AppDelegate.init()のsuper.init()直後で登録しても安全と結論(CONFIRMED)。observer登録をapplicationWillFinishLaunchingからinit()末尾へ移設。既存のACK+リトライ+重複排除機構(task-73.6/task-79)は、登録タイミングと無関係な別要因(ACK自体の消失=task-81、DistributedNotificationCenterのベストエフォート特性)に対応するため、単純化・撤去はせず維持すると判断し明記した。検証: swift build成功、プロジェクト全543テストgreen(既存のCLIInstanceRouterTests/CLIRequestDeduplicatorTests含む回帰なし)。
<!-- SECTION:FINAL_SUMMARY:END -->
