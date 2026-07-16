---
id: TASK-11
title: >-
  thread-sanitizer ジョブで FileWatcherIntegrationTests.detectsFileModification
  が高頻度で失敗する
status: In Progress
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 01:21'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/192
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #192 から移行。thread-sanitizer ジョブ（push / schedule トリガー）が直近1週間ほぼ毎回失敗。TSan のスローダウン下で waitUntilWithRetry の timeout 15秒以内に FileWatcher のコールバックが発火しない。確認した範囲で 8/8 失敗。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 thread-sanitizer ジョブで FileWatcherIntegrationTests が安定して pass する
- [x] #2 TSan 実行時のタイムアウトが適切に設定されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. waitUntilWithRetry/waitUntilWithRetryOnMainActor のデフォルト timeout=15 (TestSupport.swift) が BEFOLD_TEST_TIMEOUT_SECONDS を無視していたのが原因。
2. 単純化: 新しい仕組みは作らず、既存の testTimeout(fallback:) と同じ環境変数解決ロジックを使う testTimeoutSeconds(fallback:) を追加し、両ヘルパーのデフォルト値に適用。
3. swift test でリグレッションがないことを確認（TSan実行はCIで確認）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因: waitUntilWithRetry/waitUntilWithRetryOnMainActor のデフォルト timeout=15 がハードコードされ、CIが設定する BEFOLD_TEST_TIMEOUT_SECONDS=30 を無視していた（他のwaitUntil系は testTimeout(fallback:) 経由で環境変数を尊重済み）。修正: 既存の testTimeout(fallback:) と同じ解決ロジックを testTimeoutSeconds(fallback:) として切り出し、両ヘルパーのデフォルト値に適用（TestSupport.swift）。検証: swift build 成功、swift test（全336件）成功、BEFOLD_TEST_TIMEOUT_SECONDS=30 --sanitize=thread でも FileWatcherIntegrationTests 9件成功。ただしローカルではTSanの実スローダウンが再現できないため、AC#1（CI上での安定パス）はCI実行結果で確認が必要。
<!-- SECTION:NOTES:END -->
