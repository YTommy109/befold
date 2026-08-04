---
id: TASK-114
title: CLI バイナリ分離後の軽微な品質改善
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 12:19'
updated_date: '2026-07-23 16:56'
labels:
  - cleanup
  - cli
dependencies: []
priority: low
ordinal: 51500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで検出された軽微な問題のまとめ: (1) CLIAppLauncher.launch() に @MainActor アノテーションがなく MainActor.assumeIsolated を直接呼んでいる (2) befold-cli の統合テスト（exit-after-forward）が欠落 (3) BefoldRootCommandIntegrationTests.swift に不要な @testable import befold が残っている
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLIAppLauncher.launch() が @MainActor でアノテートされている
- [x] #2 befold-cli のフォワーディング後終了を検証する統合テストが存在する
- [x] #3 不要な @testable import befold が除去されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIAppLauncher.launch() に @MainActor を付与し、内部の MainActor.assumeIsolated を除去。呼び出し元(BefoldCLICommand.run())側で MainActor.assumeIsolated にラップ(bookmark実行と同様の形)\n2. CLIAppLauncherTests に、CLIInstanceRouter.forward の実装(post/waitForAckのみモック)を通して CLIAppLauncher.run が ACK受信後ただちに exit(0) することを検証する統合的テストを追加\n3. BefoldRootCommandIntegrationTests.swift の未使用 @testable import befold を削除
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#2について: 真の実プロセス統合テスト(befold-cli実バイナリ + 別プロセス受信者)はユーザーと協議の上、断念した。理由: befold-cliの実行ファイルはBundle.main.bundleIdentifierがnilのため『既存インスタンスあり』分岐に到達できず、必ず/usr/bin/open -aを実行してしまい実アプリ起動の副作用が発生してしまうため。代わりに、CLIInstanceRouterTestsと同じ方針(実DistributedNotificationCenterは使わずpost/waitForAckのみモック)で、CLIAppLauncher.run から実際のCLIInstanceRouter.forward実装を呼び出し、ACK受信後ただちにexit(0)することを検証するrealForwardReceivesAckAndExitsPromptlyテストを追加した。当初は実際のDistributedNotificationCenterを使うテストを書いたが、このプロジェクトのテスト実行環境(ヘッドレス/バックグラウンド実行)でNSRunningApplication.activate()や実DistributedNotificationCenterがハングするリスクが判明したため、既存のCLIInstanceRouterTestsの方針に合わせて安全な形に修正した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
3件の軽微な品質改善を実施。(1) CLIAppLauncher.launch() に @MainActor を付与し内部の MainActor.assumeIsolated を除去、呼び出し元 BefoldCLICommand.run() 側で assumeIsolated にラップ(bookmark実行と同じ形に統一)。(2) befold-cli のフォワーディング後終了を検証する統合テストとして realForwardReceivesAckAndExitsPromptly を追加。当初検討した実バイナリ+別プロセス受信者によるe2eは、befold-cliの実行ファイルがBundle.main.bundleIdentifier=nilのため『既存インスタンスあり』分岐に到達できず実アプリ起動の副作用が出るためユーザーと協議し断念、CLIInstanceRouterTestsと同方針で実forward実装(post/waitForAckのみモック)を通したexit(0)検証に変更した。(3) BefoldRootCommandIntegrationTests.swift の未使用 @testable import befold を削除。post-edit hook の swift build/swift test --skip Integration --skip FileWatcherTests がエラーなく完了。
<!-- SECTION:FINAL_SUMMARY:END -->
