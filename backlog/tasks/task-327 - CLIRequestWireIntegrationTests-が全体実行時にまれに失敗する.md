---
id: TASK-327
title: CLIRequestWireIntegrationTests が全体実行時にまれに失敗する
status: To Do
assignee: []
created_date: '2026-08-05 17:07'
updated_date: '2026-08-05 18:28'
labels:
  - test
  - flaky
dependencies: []
priority: medium
type: bug
ordinal: 508000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-319 の作業中に遭遇。`swift test` の全体実行で「全オプション付きの要求が実際の Distributed Notification を通って復元できる」（CLIRequestWireIntegrationTests.swift:53 / :65）がまれに失敗する。単独実行（--filter）では常に通る。

実測（2026-08-06、同一マシン）:
- 現ブランチ HEAD で全体実行: 失敗する回と通る回がある（連続 3 回では 3/3 通過、その前は 2 回連続で失敗）
- 失敗時のメッセージ: `waitUntilWithRetry` のタイムアウトと `received.get() → nil`
- origin/main の全体実行では失敗を再現できていない（1 回のみ実施）

当初は同セッションの ViewerStore.openFile の変更が原因かと考え、その行を消すと通ったため因果があるように見えたが、その後同一ツリーで 3 回連続通過したため**偶然の一致**と判断した。実際にはテスト自体が Distributed Notification の配送タイミングに依存しており、並列実行時の負荷で待ち時間を超えていると見られる。

調査の方向: 待機の上限（waitUntilWithRetry のリトライ回数・間隔）が負荷時に不足していないか、Distributed Notification を使う統合テストを直列化（.serialized）すべきか、通知配送がメインランループのターンを要求する点をテスト側でどう担保するか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 全体実行を 10 回繰り返しても当該テストが失敗しない
- [ ] #2 失敗が負荷・並列度のどちらに起因するかが実測で示されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-06: 同種の不安定さを ViewerWindowControllerToolbarTests「行番号アイテムはコード表示中のみ有効」（ViewerWindowControllerToolbarTests.swift:98、`(codeButton.isEnabled → false) == true`）でも観測した。単独実行と再実行では通る。全体実行時の負荷・並列度に依存する点が CLIRequestWire と共通のため、調査は 2 件まとめて行うのがよい。

2026-08-06: 全体実行が**終わらない**（テストバイナリが 100% 超の CPU を 20 分以上回し続ける）事象も 2 回連続で観測した。`sample` で採取したスタックは、多数のワーカースレッドが `-[NSAnimation _runBlocking]` → `CFRunLoopRun` で待っている状態で、メインスレッドは `swift_task_asyncMainDrainQueue` → `CFRunLoopRun`。当該セッションの変更（GitDiffLoader）とは無関係な AppKit のウィンドウアニメーション待ちに見える。プロセスを kill して再実行すると 1150 tests が 18.7 秒で通過した。ハング時の sample は scratchpad に採取したが永続化していないため、次回再現時に `sample <pid>` を取り直して保存すること。
<!-- SECTION:NOTES:END -->
