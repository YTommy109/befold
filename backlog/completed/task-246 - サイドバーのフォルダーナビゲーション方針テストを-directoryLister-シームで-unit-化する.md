---
id: TASK-246
title: サイドバーのフォルダーナビゲーション方針テストを directoryLister シームで unit 化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 10:45'
updated_date: '2026-08-01 23:13'
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
- [x] #1 対象 8 テストがスタブ lister による unit テストへ移行し、TempDir とフルウィンドウ生成が不要になる
- [x] #2 Integration 側には実 FS が本質のテストのみが残る
- [x] #3 競合(世代ガード)テストが sleep なしで決定的に検証される
- [x] #4 swift test が全てグリーン
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SidebarNavigatorFolderNavigationTests.swift(6テスト)/SidebarNavigatorGenerationTests.swift(2テスト)を新設し、対象8テストを directoryLister スタブ+StubHost で unit 化。世代ガード競合は AsyncGate.wait()/open() で決定的に再現(sleep 不使用)。移設元2ファイルからは対象テストを削除しヘッダーコメントを実態に合わせて更新。swift build 警告なし、swift test 全体 1006 tests green(新設8テストは各 0.002 秒、旧来の TempDir+フルウィンドウは不要に)。

修正ラウンド1(レビュー反映): (1)世代ガード競合テストの順序を staleTask/freshTask 明示待ちに変更し、performListing の generation ガードを一時的に外すと確実に落ちる(1 issue)ことを確認してから元に戻した。(2)navigateToChildDoesNotAutoSelect に選択候補のファイル(child.mmd)を追加し、ClearsSelection テストと区別が付く強度に戻した。(3)StubHost を SidebarNavigatorTestStubs.swift の SidebarNavigatorStubHost に集約し 3 スイートの重複を解消。検証: swift build 警告なし、swift test 全体 1006 tests green。

レビューで、移設によって 2 つのテストが実質的に検証しなくなっていたことが判明し、修正ラウンド 1(1ed8fc6)で是正した。
- 世代ガードテスト: staleGate.open() を 2 回目発行の直後に呼んでいたため task1/task2 の完了順序が未定義で、さらに pendingListingTask が最新タスクで上書きされるため await していたのは task2 のみだった。結果、世代ガードを削除しても高確率で通る状態だった。stale タスクを掴んでから fresh を await し、その後ゲートを開いて stale を待ち切る順序へ修正。実際にガードを外して当該テストが落ちることを確認済み(確認後に復元。レビューでプロダクトコードへの復元漏れが無いことも検証済み)
- navigateToChildDoesNotAutoSelect: スタブの listings がフォルダーのみで選択候補のファイルが存在せず、「選択候補があっても自動選択しない」という元の不変条件を検証できていなかった(selection = nil が「最初のファイルを選ぶ」に変わっても通る状態)。child.mmd を戻して復元
- StubHost の 3 ファイル重複を SidebarNavigatorTestStubs.swift へ集約(SidebarNavigatorHost が befold 内部 protocol のため BefoldTestSupport には置けない旨を /// に明記)
Integration に残った 2 件(navigatingUpUpdatesRootDirectory / refreshFileListPreservesFolderSelection)も実 FS が本質でないとレビューで指摘されたが、スコープを広げず TASK-256 として起票した。実 FS が本質なのは symlink テストのみ。
実行時間: 対象スイートは全体時間(約 13s、律速は GitCommandRunnerResourceLeakTests)にほぼ寄与しないため、短縮効果は測定していない。本タスクの価値はテスト分類の正確さ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigator の選択ポリシー検証 8 件を、既存の directoryLister 注入シームを使ったスタブベースの unit テストへ移設した(SidebarNavigatorFolderNavigationTests / SidebarNavigatorGenerationTests を新設)。実 FS と TempDir とフルウィンドウ生成が不要になり、Integration 側には実 FS が本質のテストが残る。世代ガードの競合再現は固定 sleep でなく AsyncGate で決定的に書いた。
レビュー指摘により、移設で失われていた検証 2 件(世代ガードを外しても通る状態、選択候補ファイルが無く自動選択しない検証が空振り)を復元し、ガードを外すと落ちることを実際に確認した。StubHost の 3 ファイル重複も共有ファイルへ集約。
効果は実行時間ではなくテスト分類の正確さ(対象スイートは全体時間にほぼ寄与しない)。
検証: swift test 1006 tests / 141 suites グリーン(実装者・レビュー担当が独立に実行)、swiftformat 差分なし、swift build 警告なし。レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
