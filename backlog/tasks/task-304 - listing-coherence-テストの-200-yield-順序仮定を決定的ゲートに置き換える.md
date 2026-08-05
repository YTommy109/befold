---
id: TASK-304
title: listing coherence テストの 200-yield 順序仮定を決定的ゲートに置き換える
status: To Do
assignee: []
created_date: '2026-08-04 16:36'
labels:
  - git-filter
  - review-finding
  - test
dependencies: []
priority: low
type: task
ordinal: 505000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の PLAUSIBLE 指摘（flaky リスク）。SidebarNavigatorListingCoherenceTests の appliesListingWithoutWaitingForGitWhenFilterIsOff（:90 付近）は「git が一覧より後に完了する」順序を 200 回の Task.yield ループで表現しており、スケジューラ依存の仮定になっている。負荷のかかった CI や別のスケジューリングでは yield が先に完了し、分離適用タスクがアサーション（:111 の `gitStatus == nil`）より先にステータスを適用して、プロダクション修正が正しくてもテストが間欠的に落ちうる。CheckedContinuation 等で「テスト側が明示的に解放するまで git が完了しない」決定的ゲートに置き換える。順序テストは想定スケジュールを固定しただけでは実プロパティを測れない（メモリの既知パターン）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テストの順序保証が yield 回数ではなく決定的な同期プリミティブで表現されている
- [ ] #2 置き換え後もテストが検証対象の退行（絞り込み OFF で一覧が git を待つ）を検出できる（修正を戻すと失敗する）
<!-- AC:END -->
