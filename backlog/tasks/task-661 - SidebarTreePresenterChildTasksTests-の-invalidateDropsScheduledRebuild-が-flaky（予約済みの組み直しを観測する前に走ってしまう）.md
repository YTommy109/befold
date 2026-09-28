---
id: TASK-661
title: >-
  SidebarTreePresenterChildTasksTests の invalidateDropsScheduledRebuild が
  flaky（予約済みの組み直しを観測する前に走ってしまう）
status: To Do
assignee: []
created_date: '2026-09-28 06:49'
labels:
  - test
  - flaky
dependencies: []
priority: medium
type: chore
ordinal: 861000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-657 の作業中に `swift test` 全件で 1 件落ち、同じツリーで `swift test --filter SidebarTreePresenterChildTasksTests` を 5 回回すと 2 回落ちた（2026-09-28、実測）。落ちるのは毎回同じ箇所で、テスト「子リストの着地で予約された組み直しは、展開を捨てると走らず、捨てた展開を開き直さない」（`invalidateDropsScheduledRebuild`）の `try #require(presenter.hasPendingRebuild)`。TASK-657 の変更（パネル窓の位置）はこのスイートと接点が無い。

## 原因の仮説（未確認）
テストは `gate.open()` の後、`Task.yield()` を最大 10000 回回して `hasPendingRebuild` が立つのを待つ。一方、予約された組み直しは走り始めに予約を nil へ戻す（テスト内のコメントのとおり）。yield の間に組み直しが走り切ると、予約が立っていた瞬間を観測できずにループを抜け、`#require` が落ちる。yield の回数と実行順に依存する観測で、TASK-642（展開テストが yield 回数に依存）と同じ型に見える。

確かめ方: 落ちた回で `issued` / 組み直しの実行回数を出し、`#require` の時点で既に組み直しが走っていたかを見る。

## 関連
TASK-642 / TASK-644 / TASK-649（いずれも Done）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 invalidateDropsScheduledRebuild を同じツリーで少なくとも 20 回連続で回して落ちない
- [ ] #2 予約が立った状態を、yield の回数や実行順に頼らずに作ってから invalidateExpansion を呼んでいる
- [ ] #3 修正を戻すと、少なくとも 1 回は落ちることを確かめている（または落ちない理由を Notes に書く）
<!-- AC:END -->
