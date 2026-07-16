---
id: TASK-11
title: >-
  thread-sanitizer ジョブで FileWatcherIntegrationTests.detectsFileModification
  が高頻度で失敗する
status: To Do
assignee: []
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/192
ordinal: 17000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #192 から移行。thread-sanitizer ジョブ（push / schedule トリガー）が直近1週間ほぼ毎回失敗。TSan のスローダウン下で waitUntilWithRetry の timeout 15秒以内に FileWatcher のコールバックが発火しない。確認した範囲で 8/8 失敗。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 thread-sanitizer ジョブで FileWatcherIntegrationTests が安定して pass する
- [ ] #2 TSan 実行時のタイムアウトが適切に設定されている
<!-- AC:END -->
