---
id: TASK-116.7
title: 固定 sleep・過大フィクスチャ・実時間性能アサーションを整理する
status: To Do
assignee: []
created_date: '2026-07-23 23:19'
labels:
  - test
  - cleanup
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 30700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テスト実行時間に無条件で乗るコストと、共有ランナー上で本質的にフレーキーな検証を取り除く。

## 1. DebouncerTests の無条件 1.8 秒

`BefoldApp/befoldTests/DebouncerTests.swift` の :19(0.5s) / :38(0.5s) / :55(0.3s) / :76(0.5s) が固定 `Task.sleep`。Debouncer の delay は 0.1 秒なので、成功していても毎回 0.5 秒待つ。

coding_rule.md:623 の「『発火する』の検証は固定 sleep ではなく `waitUntil` で条件成立を待つ」に明確に違反。`firesAfterDelay`(:8) / `coalescesRapidCalls`(:24) / `reschedulesAfterCancel`(:61) の 3 つは肯定的検証なので `LockedBox` + `waitUntil` に置換でき、約 1.3 秒短縮できる。

`cancelPreventsExecution`(:43)の 0.3s だけは否定的検証なので固定待ちが妥当。ただし delay 0.1s に対して 3 倍とする根拠のコメントが無く、coding_rule.md:625-627 の「待機時間の根拠をコメントに書く」を満たしていない。

## 2. 過大なフィクスチャ

`BefoldApp/befoldTests/NormalizedTextCacheLazyGrowthTests.swift:32` の `makeLines(2_000_000)` は約 22MB の文字列を 200 万回の補間 + join で構築する、単一で最も重いテスト。しかし検証内容は `first.text.utf8.count < fileSize / 4`(:45)だけで、チャンクは約 1000 行(約 9KB)。**サイズが load-bearing でない**ため 20 万行でも同じ結論が出る。コメント :28-31 の「20MB 超が代表サイズ」という主張も実際には検証に効いていない。

## 3. 実時間の性能アサーション

`BefoldApp/befoldTests/TextEncodingTests.swift:45-58` `detectEncodingStaysFastForLargeLegacyData` は 5MB の Shift_JIS を生成した上で `#expect(elapsed < .seconds(3))` を課す。共有 CI ランナー・TSan ジョブでは本質的にフレーキーで、失敗時は 3 秒を必ず消費する。性能回帰の検知が目的なら「線形性の検証(小/大 2 サイズの比が上限以下)」への置換、または環境変数によるスキップを検討すること。

## 4. 理由の無い .serialized

`BefoldApp/befoldTests/StringChunkReaderTests.swift:5` に `@Suite(.serialized)` が付いているが理由コメントが無い。他の 2 つの `.serialized` スイート(`FileWatcherIntegrationTests.swift:5-10`、`ViewerStoreIntegrationTests.swift:5-7`)は理由を明記しており不統一。18 テスト(うち複数が MB 級フィクスチャ)を直列化しているため、不要なら並列化で短縮できる。

## 参考: 既存の良い設計

`BefoldApp/befoldTests/TestClock.swift` + `ViewerStoreFileGoneTests.swift:9-38` の `AsyncGate` によるグレース期間テストは、仮想クロックで実時間ゼロを達成している模範例。FileWatcher / ViewerStore の統合テストもこの方式に寄せられないか、あわせて検討する価値がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Debouncer の肯定的検証が固定 sleep ではなく条件待ちで書かれている
- [ ] #2 否定的検証として残す固定待ちには、待機時間の根拠がコメントされている
- [ ] #3 テストフィクスチャのサイズが、検証内容に対して過大でない
- [ ] #4 共有ランナー上でフレーキーになる実時間の性能アサーションが残っていない
- [ ] #5 すべての .serialized スイートに直列化の理由が記載されている
<!-- AC:END -->
