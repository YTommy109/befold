---
id: TASK-661
title: >-
  SidebarTreePresenterChildTasksTests の invalidateDropsScheduledRebuild が
  flaky（予約済みの組み直しを観測する前に走ってしまう）
status: Done
assignee: []
created_date: '2026-09-28 06:49'
updated_date: '2026-09-29 08:28'
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
- [x] #1 invalidateDropsScheduledRebuild を同じツリーで少なくとも 20 回連続で回して落ちない
- [x] #2 予約が立った状態を、yield の回数や実行順に頼らずに作ってから invalidateExpansion を呼んでいる
- [x] #3 修正を戻すと、少なくとも 1 回は落ちることを確かめている（または落ちない理由を Notes に書く）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
着地ジョブと予約ジョブの間にテストが入れる保証が無いのが原因。同じスイートの collapseDropsScheduledRebuild も同型(再試行ループで回避)なので、2 件目として構造で塞ぐ: 予約した組み直しの走り始めにテスト専用の待ち(scheduledRebuildHold)を置き、両テストは予約を止めてから観測する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- 再現(修正前): スイート単位 20 回で無負荷 0/20、CPU 負荷 6 本の下で 1/20 失敗(SidebarTreePresenterChildTasksTests.swift:119 の #require(presenter.hasPendingRebuild))。仮説どおり、予約が観測前に走っていた。
- 修正: SidebarTreePresenter.scheduledRebuildHold(テスト専用・本番は常に nil)を予約 Task の先頭で await。テストは holdScheduledRebuild で予約を止め、立った状態が残る状態で invalidateExpansion / collapseFolder を呼ぶ。collapseDropsScheduledRebuild の 50 回再試行ループも撤去(同型の 2 件目なので構造で塞いだ)。
- 検証: 修正後、CPU 負荷下でスイート 30/30 通過。修正を戻す確認: invalidateExpansion の dropPendingRebuild を外すと invalidateDropsScheduledRebuild が 5/5 失敗(hasPendingRebuild・issued==1・expandedKeys.isEmpty すべて)、applyRows 側を外すと collapseDropsScheduledRebuild が 5/5 失敗。swift test --filter 'Sidebar|FileList|ViewerWindow' 592 件通過、swiftlint 変更ファイル 0 件、swiftformat 整形不要。
- 仕様文書: テストの継ぎ目の追加のみで挙動は不変のため native-app-design.md の更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
予約した組み直しの走り始めにテスト専用の待ち(scheduledRebuildHold)を置き、invalidateDropsScheduledRebuild と collapseDropsScheduledRebuild が予約を止めてから観測するようにした(後者の再試行ループも撤去)。CPU 負荷下で修正前 1/20 失敗 → 修正後 30/30 通過、修正を戻すと両テストとも 5/5 失敗することを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
