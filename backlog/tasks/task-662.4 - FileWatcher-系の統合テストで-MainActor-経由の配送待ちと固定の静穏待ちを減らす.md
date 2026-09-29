---
id: TASK-662.4
title: FileWatcher 系の統合テストで MainActor 経由の配送待ちと固定の静穏待ちを減らす
status: Done
assignee: []
created_date: '2026-09-29 04:29'
updated_date: '2026-09-29 06:57'
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
- [x] #1 FileWatcher の検知ロジックのテストが MainActor の混雑に左右されずに完了を待てる
- [x] #2 confirmWatcherArmed の固定待ちが短縮または条件待ちになっている
- [x] #3 ViewerStoreIntegrationTests の .serialized を外し、3 回連続で緑を確認している（外せない場合は理由を Notes に）
- [x] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装（977db877）:
- FileWatcher に onChangeOnWatcherQueue / onRenameOnWatcherQueue の init を足し、従来の init はそれを包んで @MainActor へ渡す convenience init にした。検知テスト 7 件中 6 件がこちらで受け取り、waitUntil / waitUntilWithRetry（壁時計予算付き）で待つ。MainActor への配送は detectsAtomicSave と ViewerStoreIntegrationTests が見る
- confirmWatcherArmed: 静穏判定 0.35s → 0.15s（デバウンス 0.05 の 3 倍）、arm 待ちを waitUntilWithRetry(interval 0.15) へ。stopPreventsCallback の固定待ち 0.4 → 0.2s。再試行間隔 0.5 → 0.2s
- ViewerStoreIntegrationTests: .serialized を外した。closeStopsWatching（0.4s 固定待ち）を削除し ViewerStoreTests.closeStopsWatcher（StopCountingWatcher）へ置換。close() から stop() を消すと落ちることを確認済み

計測（手元 / debug / --skip-build）:
| 対象 | 変更前 | 変更後 |
|---|---|---|
| FileWatcherIntegrationTests 直列（--no-parallel --filter） | 5.10 s | 2.74 s |
| ViewerStoreIntegrationTests 直列 | 1.04 s（3 件） | 0.61 s（2 件） |
| 全体並列時の FileWatcherIntegrationTests | 40.3 s | 7.4 / 10.7 / 4.3 s |
| swift test 全体 wall（befoldTests） | 43.27 s（real 46.1） | 41.74 / 40.13 / 39.50 s（real 44.1 / 42.1 / 41.4） |
全体 wall の差は 2〜4 秒で、変更前が 1 回計測のため揺らぎと区別しきれない。律速は引き続き MainActor 直列（親タスクの分析どおり）。
- .serialized 解除後の全体 swift test 3 回連続緑（2017 件）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileWatcher に通知を監視キュー上で呼ぶ init を足し、検知テストを MainActor の混雑から切り離した。confirmWatcherArmed の静穏待ちを 0.35→0.15s、ViewerStoreIntegrationTests の .serialized を解除し closeStopsWatching を単体テストへ移した。FileWatcherIntegrationTests 直列 5.10→2.74s、全体並列 3 回連続緑。
<!-- SECTION:FINAL_SUMMARY:END -->
