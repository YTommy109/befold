---
id: TASK-303
title: 絞り込み OFF へのトグルで全ウィンドウが不要な git status を実行する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 16:36'
updated_date: '2026-08-04 17:16'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: low
type: bug
ordinal: 500000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の CONFIRMED 指摘。ViewerWindowManager.toggleChangedFilesOnly（ViewerWindowManager.swift:114-116）はトグル方向に関係なく全ウィンドウで applyChangedFilesOnlyToggle → refreshGitStatuses を実行する。OFF へのトグルでは絞り込みに新しい git 状態は不要で、大きいリポジトリを複数ウィンドウで開いていると、トグルのたびにウィンドウ数分の git status サブプロセスが同時起動する。TASK-297 がナビゲーション経路で削ったのと同種の不要な git 実行。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 OFF へのトグルで git status サブプロセスが起動しない（バッジは既存状態を維持）
- [x] #2 ON へのトグルでは従来どおり最新の git 状態で絞り込まれる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: 呼び出し側から方向を渡す/新フラグを持つのではなく、syncDisplayPreferences() が同期した直後の fileListModel.showChangedFilesOnly をそのまま判定に使う（新規状態ゼロ）。
2. TDD: SidebarNavigatorGitStatusTests の applyingChangedFilesOnlyPreference をパラメタ拡張し、initialState/targetState を持たせて「OFF へのトグル適用 → git 取得 0 回」ケースを追加する。先に失敗を確認する。
3. SidebarNavigator.applyChangedFilesOnlyToggle に guard fileListModel.showChangedFilesOnly else { return } を入れる。
4. swift test で該当スイートを実行し、修正を戻すと落ちることも確認する。
5. swiftformat/swiftlint のベースライン差分ゼロを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化検討: 呼び出し側から方向を渡す・新しいフラグを持つといった状態追加はせず、syncDisplayPreferences() が同期した直後の fileListModel.showChangedFilesOnly をそのまま判定に使った（新規状態ゼロ、1 行の guard）。

実装: SidebarNavigator.applyChangedFilesOnlyToggle に guard fileListModel.showChangedFilesOnly else { return } を追加。OFF へのトグルでは refreshGitStatuses を発行しない。既存の gitStatus は fileListModel に残るためバッジは維持される。gitIndexWatch も解除されないので、以後の .git/index 変更では従来どおり更新される。

検証:
- SidebarNavigatorGitStatusTests の applyingChangedFilesOnlyPreference を initialState/targetState 付きにパラメタ拡張し、「OFF へのトグル適用 → git 取得 0 回」ケースを追加。
- 赤の確認: 修正前は (gitCalls → 2) == (期待 1) で失敗。
- 緑の確認: swift test --skip Integration --skip FileWatcherTests → 1012 tests / 141 suites passed。
- 修正だけ戻す revert チェック: guard を消すと同じケースが再び失敗（gitCalls → 2）。テストが修正をゲートしていることを実測。
- Integration 含む関連スイート: --filter 'ChangedFilesOnly|ViewerWindowManagerIntegration|SidebarNavigator' → 35 tests / 9 suites passed。
- swiftformat: 0 files formatted（差分なし）。swiftlint: 変更 2 ファイルの警告は HEAD 時点と同一の 3 件（file_length / opening_brace / type_body_length）で、新規違反なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigator.applyChangedFilesOnlyToggle が ON/OFF どちらのトグルでも refreshGitStatuses を発行していたため、絞り込み OFF にするたびに開いているウィンドウ数だけ不要な git status サブプロセスが同時起動していた。同期済みの fileListModel.showChangedFilesOnly を判定に使う 1 行の guard を入れ、ON のときだけ取り直すようにした（新規状態なし・再列挙も従来どおり発生しない）。SidebarNavigatorGitStatusTests のパラメタに OFF ケース（git 取得 0 回）を追加し、修正前は失敗・修正後は成功、guard を戻すと再び失敗することまで実測で確認。ユニット 1012 件と関連 Integration 35 件が通り、swiftformat/swiftlint の差分もゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
