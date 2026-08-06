---
id: TASK-335
title: FileWatcherIntegrationTests のリネーム検知が全体実行時にまれに失敗する
status: To Do
assignee: []
created_date: '2026-08-06 02:56'
labels:
  - test
  - flaky
dependencies: []
priority: medium
type: bug
ordinal: 601000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-327 の検証中（全体実行 26 回）に 1 回だけ観測した。`swift test` の全体実行で FileWatcherIntegrationTests の detectsRenameWithinSameDirectory（FileWatcherIntegrationTests.swift:135-136）と detectsMoveToAnotherDirectory（同 :186-187）が同時に失敗した。いずれも renamed が nil のまま 15 秒の待機予算を使い切っている。

TASK-327 で確定した原因（full suite 実行中はメインアクターが飽和し、メインアクターの一巡に 5〜8 秒かかる）と同じ系統の可能性があるが、こちらは FileWatcher の DispatchSource コールバック経路であり未確認。まず待機がメインアクター/メインキューの一巡に依存しているかを確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 全体実行を 10 回繰り返しても当該 2 テストが失敗しない
- [ ] #2 失敗の原因（メインアクター飽和か、DispatchSource のイベント取りこぼしか）が実測で示されている
<!-- AC:END -->
