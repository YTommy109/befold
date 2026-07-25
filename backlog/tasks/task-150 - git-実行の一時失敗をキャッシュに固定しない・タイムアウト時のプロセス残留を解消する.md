---
id: TASK-150
title: git 実行の一時失敗をキャッシュに固定しない・タイムアウト時のプロセス残留を解消する
status: To Do
assignee: []
created_date: '2026-07-25 11:31'
labels:
  - path-reference
dependencies: []
priority: medium
type: task
ordinal: 226000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
パフォーマンスレビュー指摘（低×2）+ コアレビュー指摘。(1) GitCommandFileIndex.swift L46-51, L59-62: rev-parse のタイムアウト等で nil が返ると「git 管理外」としてアプリ再起動まで固定され、ls-files タイムアウト時は空リストが fingerprint 付きでキャッシュされ次の commit までリンク化が全停止する（性能保護機構の副作用による機能劣化）。(2) GitCommandRunner.swift L54-64: terminate() は SIGTERM のみで、読み取りスレッドが readDataToEndOfFile() でブロックしたまま残留しうる。応答しない NFS リポジトリ等で漏れが蓄積する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 失敗（nil / 空）結果はキャッシュせず次回リトライする、または短い TTL 付きネガティブキャッシュにする
- [ ] #2 terminate() 後に pipe.fileHandleForReading を close して読み取りスレッドを EOF で解放する（SIGKILL フォールバックも検討する）
- [ ] #3 失敗→リトライの挙動をテストで固定する
<!-- AC:END -->
