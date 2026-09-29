---
id: TASK-665
title: ViewerWindowControllerDiffPendingTests の遅延解決テストが並列実行でゲート待ち 15 秒の上限に達して落ちる
status: To Do
assignee: []
created_date: '2026-09-29 07:52'
labels:
  - bug
  - test
dependencies: []
priority: medium
ordinal: 866000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-09-29、TASK-662.6 の計測中に HEAD（6a81daaa）の `swift test`（並列）で 1 回落ちた（同じ日の並列 4 回中 1 回。直列では未観測）。

- 落ちたテスト: `ViewerWindowControllerDiffPendingTests.keepsResolvedDiffWhenBaseDirectoryResolutionLandsLate`
- 記録: `ViewerWindowControllerDiffPendingTests.swift` の `SlowRootGitFileIndex.repositoryRoot` で「同期待機が 15.0 秒で上限に達した」が 2 件（解決が 2 回呼ばれ、両方ゲートで塞がれている）
- 構造: TASK-662.5 で `Thread.sleep(0.5)` を `BlockingGate` へ置き換えた。ゲートは協調スレッドを同期に塞いだまま、テスト本体が `await controller.store.loadTask?.value` → `await controller.diffRefreshTask?.value` を終えて `gate.open()` に着くのを待つ。並列時は MainActor のキュー待ちで 1 回の配送が 10 秒級になる（TASK-662 の実測で passed after 35〜44 秒）ため、open に着く前に 15 秒の上限を超えうる

未確認: 上限超過が MainActor の混雑だけで説明できるか（塞がれた協調スレッド 2 本が loadTask 側の進行も止めている可能性）。落ちた回のサンプルは取れていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 並列実行で落ちる条件（混雑だけか、塞いだ協調スレッドが待ち先の進行を止めているか）を特定している
- [ ] #2 ゲートの上限を延ばす形ではなく、待ちの構造で直っている
- [ ] #3 並列の全体実行で当該テストが 5 回連続緑
<!-- AC:END -->
