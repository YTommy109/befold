---
id: TASK-296
title: 変更ファイル絞り込みのトグル時に git ステータスが更新されない
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 14:46'
updated_date: '2026-08-04 15:48'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: medium
type: bug
ordinal: 494000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の検証済み指摘（CONFIRMED）。

TASK-291 で toggleChangedFilesOnly から refreshAllSidebars() を外し、syncDisplayPreferences()（Bool 2 つのミラーのみ）に置き換えた結果、トグル時に git ステータスの再取得が一切走らなくなった。作業ツリーの編集は .git/index を触らないため GitIndexWatch は発火せず、キーウィンドウのままなら windowDidBecomeKey も再発火しないので、古いスナップショットのまま絞り込みが適用される。

該当: BefoldApp/befold/App/ViewerWindowManager.swift:115
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ターミナルでファイルを編集/revert した直後にトグルしても、絞り込み結果が最新の git 状態を反映する
- [x] #2 バックグラウンドウィンドウの絞り込みも古い git ステータスのまま取り残されない
- [x] #3 TASK-291 の「トグルでサイドバー全体を再読み込みしない」性質は維持する（一覧の再列挙は行わない）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarNavigator に applyChangedFilesOnlyToggle() を追加（表示述語の同期 + refreshGitStatuses(.always)、再列挙はしない）
2. ViewerWindowManager.toggleChangedFilesOnly が全ウィンドウでそれを呼ぶ
3. テスト: トグル適用で git 取得は 1 回増え、列挙は増えないことを検証（TASK-291 の性質維持）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SidebarNavigator.applyChangedFilesOnlyToggle()（表示述語の同期 + refreshGitStatuses(.always)）を追加し、ViewerWindowManager.toggleChangedFilesOnly が全ウィンドウでこれを呼ぶようにした。新しい状態は増やさず既存の refreshGitStatuses を使い回すだけで済んだ（単純化検討の結果、専用の鮮度フラグ等は不要）。

検証: SidebarNavigatorGitStatusTests を「同期のみ=git 取得 0 / トグル適用=git 取得 1、いずれも再列挙 0」のパラメータ化テストに統合。refreshGitStatuses() を外すとトグル側ケースが落ちることを実測済み（修正なしで失敗することを確認）。swift test 1089 件通過（CLIRequestWireIntegrationTests の Distributed Notification が 1 回 flaky に落ちたが単独再実行で通過、本変更と無関係）。swiftlint は main 相当（HEAD 版ファイル）と同一の 4 件のみでベースライン差分ゼロ。SidebarNavigator.swift は file_length 400 行の上限に触れるため、追加分と同数のコメント行を圧縮した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
変更ファイル絞り込みのトグル時に git 状態を取り直すようにした（作業ツリーの編集は .git/index を動かさず index 監視も windowDidBecomeKey も発火しないため、古いスナップショットで絞り込まれていた）。SidebarNavigator に applyChangedFilesOnlyToggle() を追加し、ViewerWindowManager が全ウィンドウで呼ぶ。一覧の再列挙は行わず TASK-291 の性質を維持。パラメータ化テストで「再列挙 0・git 取得は経路ごと」を検証し、修正を戻すと落ちることも確認。
<!-- SECTION:FINAL_SUMMARY:END -->
