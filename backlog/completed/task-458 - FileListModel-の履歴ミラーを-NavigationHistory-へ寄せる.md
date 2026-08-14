---
id: TASK-458
title: FileListModel の履歴ミラーを NavigationHistory へ寄せる
status: Done
assignee: []
created_date: '2026-08-12 01:54'
updated_date: '2026-08-13 07:46'
labels:
  - chore
dependencies: []
priority: low
ordinal: 682000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
FileListModel の backHistory / forwardHistory / canGoBack / canGoForward は NavigationHistory が既に持つ知識の二重表現で、SidebarHistoryController.refreshState が毎回写している。写し忘れれば戻る/進むボタンの有効状態だけが古くなる形。

寄せるには View（HistoryButtonView）が @Observable 経由で読んでいる経路を保つ必要があるため、NavigationHistory 側を @Observable にして FileListModel が参照を持つ形にする。TASK-443 では影響範囲が別（App/ 配下の履歴制御）のためスコープ外とした。

出典: TASK-443 で回した responsibility-reviewer の指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 FileListModel が履歴の写しを stored property として持たない
- [x] #2 戻る/進むボタンの有効状態が NavigationHistory の変化で更新される（テストで担保）
- [x] #3 swift test が既存どおり通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. NavigationHistory を SidebarHistoryController から読み取り公開し、SidebarNavigator.navigationHistory / ViewerWindowController.navigationHistory で橋渡しする
2. FileListModel から backHistory / forwardHistory / canGoBack / canGoForward を削除する
3. ViewerToolbarHost に navigationHistory を追加し、applyHistoryState を NavigationHistory 直読みへ変更する
4. ViewerWindowController の ViewerMenuValidationSource 準拠(canGoBack/canGoForward)を navigationHistory 由来にする
5. 既存テストの参照を controller.canGoBack 等へ付け替え、履歴 push 後にツールバーの戻るボタンが有効化されることを検証するテストを追加する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
起票時の前提「View(HistoryButtonView)が @Observable 経由で履歴を読む」は実コードと異なっていた。履歴の読み手は ViewerToolbarController.applyHistoryState（historyStateDidChange 契機の pull）と ViewerMenuValidator（メニュー validate 契機の pull）の 2 つで、いずれも命令的に読む。よって NavigationHistory を @Observable 化する必要はなく、SidebarNavigator.navigationHistory / ViewerWindowController.navigationHistory で読み取り公開して直接読ませる形に単純化した。

検証: swift test 1479 tests / 234 suites 全通過。新規テスト historyButtonFollowsNavigationHistory は、applyHistoryState の isEnabled を false に潰すと落ちることを実測で確認（元に戻して再度パス）。swiftlint は変更ファイルで警告ゼロ、swiftformat 差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
FileListModel の backHistory / forwardHistory / canGoBack / canGoForward を削除し、ツールバー（ViewerToolbarController）とメニュー判定（ViewerMenuValidator）が SidebarHistoryController の NavigationHistory を直接読む形へ寄せた。写しが無くなったため refreshState は host への通知のみになる。swift test 全通過と、修正を潰すと落ちる新規テストで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
