---
id: TASK-246
title: サイドバーのフォルダーナビゲーション方針テストを directoryLister シームで unit 化する
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-01 10:45'
updated_date: '2026-08-01 22:50'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 448000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowControllerIntegrationTests.swift:139-238 の 6 テスト(navigateToFolderToParentWorks / RefusesAboveHomeDirectory / navigateToChild 3 種 / navigateToParentSelectsPreviousChild)と SidebarNavigatorIntegrationTests.swift:116-165 の 2 テスト(世代ガード競合 / フィルタ持続)は、SidebarNavigator の選択ポリシー検証であり実 FS の列挙結果そのものは本質でない。現状は makeHomeTempDir + フルウィンドウ(WKWebView 込み)+ 実列挙を 8 回繰り返している。
SidebarNavigator には directoryLister: (URL, SortOrder, Bool) async -> [FileListEntry] の注入シームが既にあり(SidebarNavigator.swift:32,57)、SidebarNavigatorBaseDirectoryTests.swift:27-44 が unit 化の前例。スタブ lister + StubHost で unit へ移し、世代ガード競合は sleep でなく continuation で決定的に制御する。
実 FS が本質のテスト(symlink 解決、.hidden の出現等)のみ Integration に残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 対象 8 テストがスタブ lister による unit テストへ移行し、TempDir とフルウィンドウ生成が不要になる
- [ ] #2 Integration 側には実 FS が本質のテストのみが残る
- [ ] #3 競合(世代ガード)テストが sleep なしで決定的に検証される
- [ ] #4 swift test が全てグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarNavigatorBaseDirectoryTests.swift のパターン(StubHost + directoryLister 注入 + makeIsolatedDefaults)を踏襲し、
   新規 unit テストファイル 2 本を befoldTests/ に追加する。
   a. SidebarNavigatorFolderNavigationTests.swift:
      ViewerWindowControllerIntegrationTests.swift:141-238 の 6 テスト
      (navigateToFolderToParentWorks / RefusesAboveHomeDirectory / navigateToChildDoesNotAutoSelect /
       navigateToChildDoesNotAutoOpenFile / navigateToChildWithoutFilesClearsSelection /
       navigateToParentSelectsPreviousChild)を SidebarNavigator.navigateToFolder 単体呼び出しへ移植する。
      実ディレクトリは作らず、ホームディレクトリ配下の非実在 URL + ディレクトリごとに固定エントリを返す
      スタブ directoryLister([String: [FileListEntry]] 相当)で代替する。
      「ファイルが自動的に開かれない」は StubHost.performFileSwitch の呼び出し有無で検証する。
   b. SidebarNavigatorGenerationTests.swift:
      SidebarNavigatorIntegrationTests.swift:115-164 の 2 テスト
      (rapidNavigateToFolderDiscardsStaleResult / filterTextPersistsAcrossFolderNavigation)を移植する。
      世代ガード競合は固定 sleep でなく BefoldTestSupport.AsyncGate で 1 回目の directoryLister 呼び出しを
      止めてから 2 回目を発行し、ゲートを開けて確定的に古い結果が捨てられることを検証する。
2. 移設元(ViewerWindowControllerIntegrationTests.swift / SidebarNavigatorIntegrationTests.swift)から
   該当 8 テストを削除し、スイート先頭のドキュメントコメント(何を Integration に残すかの説明)を
   実態(symlink 解決・隠しファイル出現・rename 後の実列挙・rootDirectory 追従・フォルダー選択保持など)に
   合わせて更新する。
3. cd BefoldApp && swiftformat . && swift build(警告なし)&& swift test 全体グリーンを確認する。
4. セルフレビュー: 移設前後で不変条件(選択が nil のまま/保持される、performFileSwitch 未呼出、
   世代ガードで古い結果が破棄される、filterText 保持)が失われていないか確認してからコミットする。
<!-- SECTION:PLAN:END -->
