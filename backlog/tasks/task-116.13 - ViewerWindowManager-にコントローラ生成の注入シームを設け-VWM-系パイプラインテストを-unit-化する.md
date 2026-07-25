---
id: TASK-116.13
title: ViewerWindowManager にコントローラ生成の注入シームを設け VWM 系パイプラインテストを unit 化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 13:11'
updated_date: '2026-07-25 00:41'
labels:
  - test
  - cleanup
  - refactor
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 75000
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
- [x] #1 ViewerWindowManager にコントローラ生成の store fileReader/watcherFactory/directoryLister を注入するシームがあり本番挙動は不変
- [x] #2 VWM/DisplayOverrides/SessionRestorer のうちサイドバー実列挙に依存しないテストが unit(InMemoryFileReader 等)へ移設されている
- [x] #3 サイドバー entries・隠しファイル・DirectoryLister 実 FS 依存のテストは Integration に残っている
- [x] #4 swift test / jest が green で回帰なし
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の結論を反映: ViewerWindowController が既に store:/directoryLister: を受け取れるため、VWM には新規の抽象を作らず 2 つの透過引数(makeStore: ((URL) -> ViewerStore)? = nil, directoryLister = DirectoryLister.listEntries)のみ追加する。既定値により本番挙動は不変。
2. openViewer() の ViewerWindowController 生成箇所へ store: makeStore?(url) と directoryLister: を渡す。
3. befoldTests に共有ファクトリを用意し、InMemoryFileReader + MockFileWatcher + 空 directoryLister でモック化した VWM を組み立てられるようにする。
4. サイドバー実列挙に依存しないテストを unit ファイルへ移設する(ViewerWindowManagerTests / ViewerWindowManagerDisplayOverridesTests / SessionRestorerTests)。
5. サイドバー entries・隠しファイル・DirectoryLister 実 FS 依存のテストは Integration に残し、各ファイル冒頭の据え置き理由コメントを実態に合わせて更新する。
6. swift test を実行し green を確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
当初方針(store fileReader / watcherFactory / directoryLister の 3 シーム新設)は不要と判断した。ViewerWindowController.init が既に store: (ViewerStore? = nil) と directoryLister: を受け取れる(ViewerWindowController.swift:100-101)ため、VWM 側は既存シームへ値を透過させるだけでよい。ViewerStore 自身が watcherFactory / fileReader を受け取れる(ViewerStore.swift:137-143)ので、モック化はテスト側で ViewerStore を組み立てて渡す形で完結する。新規の抽象を増やさない分、本番コードの変更は openViewer の引数追加のみに収まる。

実装(当初方針からの逸脱と理由):
ViewerWindowManager へ追加したのは makeStore: ((URL) -> ViewerStore)? = nil と directoryLister の 2 引数のみ。AC#1 が挙げる「store fileReader / watcherFactory / directoryLister」の 3 シームを個別に新設しなかったのは、ViewerWindowController が既に store: と directoryLister: を受け取れ(ViewerWindowController.swift:100-101)、ViewerStore 自身が fileReader と watcherFactory を受け取れる(ViewerStore.swift:137-143)ため。テストが組み立てた ViewerStore を makeStore で渡せば、fileReader も watcherFactory も結果的に注入できる。新しい抽象を増やさずに同じ到達点へ届くため、この形を採った。既定値(nil / DirectoryLister.listEntries)により本番の生成経路は現行と完全に同一。

移設内訳:
- 新規 befoldTests/MockedViewerWindowManager.swift: InMemoryFileReader + MockFileWatcher + 空の directoryLister で VWM を組み立てる共有フィクスチャ。3 つの unit スイートが共有する。
- ViewerWindowManagerTests(unit): 15 件を移設(既存の isDetachedFromSpace と合わせて 16 件)。
- ViewerWindowManagerDisplayOverridesTests(unit, 新規): 5 件を移設(パラメタライズ 1 件を含む)。
- SessionRestorerTests(unit, 新規): 3 件を移設。SessionRestorer は既に fileReader を注入可能(SessionRestorer.swift:22)だったため、フィクスチャと同じ InMemoryFileReader を渡すだけで unit 化できた。
- SessionRestorerIntegrationTests.swift は全件が unit へ移り空になったため削除した。
- Integration 残置: ViewerWindowManagerIntegrationTests 5 件(隠しファイルのサイドバー反映 4 件 + DirectoryLister 実 FS 解決を使う multipleCLITargetsEachOpenSeparateWindow)、ViewerWindowManagerDisplayOverridesIntegrationTests 1 件(entries の並び替え結果を実列挙で検証)。各ファイル冒頭の据え置き理由コメントを実態に合わせて書き換えた。

AC#4 の jest について: 本リポジトリに package.json は存在せず JS テストランナーは未導入のため、swift test のみで判定した(JS 側のテスト基盤導入は TASK-140 系の範囲)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowManager に makeStore / directoryLister の 2 つの注入シームを追加し、openViewer が生成する ViewerWindowController へ透過させた。既存シーム(ViewerWindowController の store:/directoryLister:、ViewerStore の fileReader/watcherFactory)を再利用したため新しい抽象は増えていない。共有フィクスチャ MockedViewerWindowManager を追加し、実 FS 列挙に依存しない 23 件を ViewerWindowManagerTests / ViewerWindowManagerDisplayOverridesTests / SessionRestorerTests(後 2 者は新規)へ unit として移設、空になった SessionRestorerIntegrationTests.swift を削除した。実列挙が検証対象そのものの 6 件は Integration に残し理由をコメント化した。検証は swift test が 607 tests / 84 suites で pass(移設前は 593/77)、swiftformat --lint が 0/179 files require formatting。
<!-- SECTION:FINAL_SUMMARY:END -->
