---
id: TASK-246
title: サイドバーのフォルダーナビゲーション方針テストを directoryLister シームで unit 化する
status: To Do
assignee: []
created_date: '2026-08-01 10:45'
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
