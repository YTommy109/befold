---
id: TASK-116.13
title: ViewerWindowManager にコントローラ生成の注入シームを設け VWM 系パイプラインテストを unit 化する
status: To Do
assignee: []
created_date: '2026-07-24 13:11'
labels:
  - test
  - cleanup
  - refactor
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-116.12 の続き。116.12 で openViewer の存在ガードは注入 fileReader 経由になったが、openViewer が内部生成する ViewerWindowController が実 store(DefaultFileReader)・実 FileWatcher・サイドバー DirectoryLister 列挙を踏むため、VWM 系テストは unit 化できず Integration に据え置いた(ユーザー判断)。

## 対応方針
ViewerWindowManager に、生成するコントローラの store fileReader / watcherFactory / directoryLister を注入できるシーム(生成用クロージャまたは各ファクトリ)を追加し、本番は現行既定(DefaultFileReader / FileWatcher / DirectoryLister.listEntries)と同一挙動を維持する。

## unit 化できる見込み(dict/session/frame/サイドバー開閉状態 系, ~8件)
- ViewerWindowManagerIntegrationTests: openViewerReusesControllerForSamePath, closingWindowRemovesControllerAndNotesClosed, openViewerRecordsRecentDocument, renameUpdatesRecentDocuments, windowForPathReturnsOpenWindow, switchFileUpdatesControllerKeyAndSession, openViewerPersistsDefaultClosedSidebarStateForNewFile, openViewerKeepsOwnSavedSidebarState, openViewerInheritsLastActiveWindowSidebarState, openViewerForceSidebarVisibleOverridesResolvedDefault, openViewerKeepsOwnSavedWindowFrame, openViewerInheritsLastActiveWindowFrame, openViewerLeavesWindowFrameUnsetWhenNothingToInherit, singleCLITargetOpensExactlyOneWindow, switchToFileOpenInAnotherWindowIsRejected
- ViewerWindowManagerDisplayOverridesIntegrationTests: サイドバー entries を検証しない 5件
- SessionRestorerIntegrationTests: 3件

## Integration 据え置き(シーム導入後も実 FS 列挙が対象そのもの)
- サイドバー entries/隠しファイル系(toggleHiddenFiles*, setHiddenFiles*, applyDisplayOverridesRefreshesSidebarEntries)
- multipleCLITargetsEachOpenSeparateWindow(DirectoryLister.isDirectory/resolveFileToOpen 実 FS)

## 完了後
unit へ戻したものは対応する unit ファイル(ViewerWindowManagerTests 等)へ InMemoryFileReader + MockFileWatcher + 空 directoryLister で移設する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerWindowManager にコントローラ生成の store fileReader/watcherFactory/directoryLister を注入するシームがあり本番挙動は不変
- [ ] #2 VWM/DisplayOverrides/SessionRestorer のうちサイドバー実列挙に依存しないテストが unit(InMemoryFileReader 等)へ移設されている
- [ ] #3 サイドバー entries・隠しファイル・DirectoryLister 実 FS 依存のテストは Integration に残っている
- [ ] #4 swift test / jest が green で回帰なし
<!-- AC:END -->
