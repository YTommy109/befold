---
id: TASK-662.4
title: FileWatcher 系の統合テストで MainActor 経由の配送待ちと固定の静穏待ちを減らす
status: To Do
assignee: []
created_date: '2026-09-29 04:29'
labels: []
dependencies: []
parent_task_id: TASK-662
priority: medium
ordinal: 860000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`FileWatcherIntegrationTests` は直列実行で最も重いスイート（3.9 秒）。並列時は各テストが 40 秒超かかって見える。

- `FileWatcher` の `onChange` / `onRename` は `Task { @MainActor in ... }` で届くため、並列実行でメインキューが混むと 1 回の配送が 10 秒級になる（`BefoldTestSupport/Waiting.swift` の TASK-335 の実測）。テストは 1 件あたり 2〜4 回往復する
- `befoldTests/TestSupport.swift` の `confirmWatcherArmed` が静穏判定で `Task.sleep(0.35s)` を通常 2 回行い、7 件中 6 件が呼ぶ。ほかに固定待ち 0.15 秒 / 0.4 秒、リトライ間隔 0.5 秒
- `ViewerStoreIntegrationTests` は `@Suite(.serialized)`。同じ根拠で直列化していた `FileWatcherIntegrationTests` は既に解除済み（ファイル冒頭の doc）。`closeStopsWatching` は `Task.sleep(0.4s)` 固定で、`ViewerStoreTests.openFileStopsPreviousWatcher` と同じ `StopCountingWatcher` 形の単体テストで足りる

案（レビュー時点）: `FileWatcher` に配送先を差し替える口を足し、テストは監視キュー上で受け取る。MainActor へ渡ることの確認は少数に残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 FileWatcher の検知ロジックのテストが MainActor の混雑に左右されずに完了を待てる
- [ ] #2 confirmWatcherArmed の固定待ちが短縮または条件待ちになっている
- [ ] #3 ViewerStoreIntegrationTests の .serialized を外し、3 回連続で緑を確認している（外せない場合は理由を Notes に）
- [ ] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->
