---
id: TASK-530
title: サイドバーが読み込み中に「対応ファイルがありません」を一瞬表示する
status: Done
assignee: []
created_date: '2026-08-19 13:31'
updated_date: '2026-08-19 14:02'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 772000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
新規タブ・新規ウィンドウを開いた直後（およびフォルダー移動直後）、サイドバーに一瞬だけ「対応ファイルがありません」が表示され、その後で改めてファイル一覧が出る。

原因（調査済み）: サイドバーが「まだ読み込んでいない」と「本当に空」を区別していない。
- 新規ウィンドウは意図的に entries: [] で作られる（ViewerWindowAssembler.swift:34-43。ネットワークボリューム上のフォルダでウィンドウ表示がディレクトリ列挙を待たないための設計判断）
- 一覧は sidebar.refreshFileList()（ViewerWindowController.swift:321-323）→ SidebarListingCoordinator.performListing（SidebarListingCoordinator.swift:159-199）の Task で非同期に届く
- その間 FileListView.swift:64 は if entries.isEmpty だけで判定し、SidebarEmptyState.reason(for:)（SidebarEmptyState.swift:92-100）は didFailListing == false・フィルタ無しなので .noSupportedFiles（sidebar.empty）を返す

「変更のみ表示」が ON のときは git status サブプロセスの完了まで待つ（SidebarListingCoordinator.swift:177-178）ため、この誤った空表示は目に見えて長くなる。

単純化の方針: 新しい状態を足す必要はない。区別に必要な FileListModel.hasLoadedEntries は既に存在し（FileListModel.swift:100-103、「ウィンドウは一覧を空で作って非同期に埋める」とコメント済み）、プレビュー側の FolderListingView.swift:175-177 は同じ区別を実装済み（未到着 nil の間は「まだ答えが出ていないので何も言わない」）。サイドバーだけがこの非対称を持っているので、SidebarEmptyContext に hasLoadedEntries を運ばせて空表示をガードすれば既存の設計に揃う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 一覧の非同期列挙が着地するまでの間、サイドバーに空状態メッセージが表示されない
- [x] #2 列挙が着地して本当に 0 件だった場合は従来どおり sidebar.empty が表示される
- [x] #3 列挙失敗（didFailListing）・名前フィルタ・変更のみ表示の各空状態文言が退行していない（SidebarEmptyState.reason(for:) の 5 分岐）
- [ ] #4 「変更のみ表示」ON で git status 待ちの間も空状態メッセージが出ないことを確認する
- [x] #5 SidebarEmptyState.reason(for:) と FileListView の表示条件に対するユニットテストを追加し、修正を戻すと落ちることを確かめる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SidebarEmptyState.reason(for:) を Optional に変え、hasLoadedEntries が false の間は nil（＝何も言わない）を返すようにした。SidebarEmptyContext に hasLoadedEntries を追加（デフォルト引数なし）し、FileListView 経路は SidebarEmptyContext(model:) が model.hasLoadedEntries を運ぶ。FolderListingView は到着済み分岐の中なので true 固定。新しい状態は足していない。

検証: swift test 1671 件 all pass。ガード行を 'guard true' に潰すと新規 3 テストが落ちることを実測（reason が .noSupportedFiles / .gitChangeAndNameFilter を返す）。swiftlint は変更 3 ファイルで指摘ゼロ。

AC #4（変更のみ表示 ON での目視）は未チェック: 背景ジョブでは GUI 確認が回せないため。ガードは git 待ちかどうかに依らず「一覧未到着なら出さない」で効くので、ユニットテスト『一覧が届いていなければ、絞り込みが効いていても何も言わない』が同じ条件を押さえている。目視は次に対話セッションでアプリを起動したときに行う。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの空状態を「一覧が届いてから」だけ出すようにした。SidebarEmptyState.reason(for:) を Optional 化し、SidebarEmptyContext.hasLoadedEntries が false の間は nil を返す。swift test 1671 件 pass、ガードを潰すと新規テスト 3 件が落ちることを実測。
<!-- SECTION:FINAL_SUMMARY:END -->
