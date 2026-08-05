---
id: TASK-304
title: listing coherence テストの 200-yield 順序仮定を決定的ゲートに置き換える
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-08-04 16:36'
updated_date: '2026-08-05 01:49'
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
- [x] #1 テストの順序保証が yield 回数ではなく決定的な同期プリミティブで表現されている
- [x] #2 置き換え後もテストが検証対象の退行（絞り込み OFF で一覧が git を待つ）を検出できる（修正を戻すと失敗する）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
appliesListingWithoutWaitingForGitWhenFilterIsOff の loadGitStatuses を 200 回 Task.yield ループから BefoldTestSupport.AsyncGate による明示的な同期ゲートへ置き換える。gate.wait() で git 結果の返却を止め、pendingListingTask 完了後に gitStatus==nil を検証してから gate.open() する。ただし pendingListingTask は Task<Void, Never> のため、素の await は退行時(一覧が git 完了を待つよう変わったとき)に無限停止しうる。waitUntilOnMainActor によるタイムアウト付きポーリングに置き換え、退行時は確実に失敗させる。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: AsyncGate 導入 + waitUntilOnMainActor によるタイムアウト付き待機に置き換え。検証: (1) 通常系 swift test --filter SidebarNavigatorListingCoherenceTests が 0.058 秒で green (2) SidebarNavigator.performListing の couplesGitStatus を一時的に true に固定して退行を再現したところ、素の await navigator.pendingListingTask?.value のままでは 100 秒超待っても無限停止(プロセス kill が必要)することを確認。waitUntilOnMainActor 版に変更後は同じ退行がプリコミットフックの全テスト実行内で 11.974 秒で 2 issues の失敗として確実に検出されることを確認(swift test --skip Integration --skip FileWatcherTests のフック出力)。検証後、production コードの一時変更は元に戻し済み。@Suite(testTimeLimit()) は Task<Void, Never> のキャンセル不能な await には効果が無いことを実測で確認したため採用しなかった(waitUntilOnMainActor の内部タイムアウトのみで十分)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigatorListingCoherenceTests.appliesListingWithoutWaitingForGitWhenFilterIsOff の loadGitStatuses スタブから 200 回 Task.yield ループを削除し、BefoldTestSupport.AsyncGate による明示的なゲートに置き換えた。git 結果は gate.open() まで返らないため、pendingListingTask 完了時点で gitStatus==nil であることはスケジューラの挙動に関わらず保証される。あわせて、退行(絞り込み OFF でも一覧が git 完了を待つ)時に素の await が Task<Void, Never> ゆえ無限停止する問題を発見し、waitUntilOnMainActor のタイムアウト付きポーリングに置き換えて解消した。検証: 通常系は swift test --filter SidebarNavigatorListingCoherenceTests で green(0.058秒)。couplesGitStatus を一時的に true 固定して退行を再現し、置き換え後のテストがプリコミットフックの全体テスト実行内で 11.974 秒・2 issues の失敗として確実に検出することを確認(修正前の素の await では 100 秒超で無限停止することも確認済み)。検証用の production コード変更は元に戻し済み。
<!-- SECTION:FINAL_SUMMARY:END -->
