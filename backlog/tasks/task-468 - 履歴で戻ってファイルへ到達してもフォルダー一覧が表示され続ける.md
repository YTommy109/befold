---
id: TASK-468
title: 履歴で戻ってファイルへ到達してもフォルダー一覧が表示され続ける
status: To Do
assignee: []
created_date: '2026-08-13 06:27'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 691000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 現象

ウィンドウ左上の history back ("<") ボタンで戻っていくと、履歴の途中でフォルダーを通過してプレビューエリアにフォルダー一覧が表示される。そこからさらに戻ってファイル提示のエントリに到達しても、そのファイルが表示されずフォルダー一覧が表示され続ける。

## 調査結果（原因）

根本原因は **履歴エントリが「フォルダー一覧を出していたか／ファイルを出していたか」を保持していない** こと。`HistoryEntry` は `{ directory, file }` の 2 値のみ（`BefoldApp/befold/App/NavigationHistory.swift:7-12`）で、記録側も選択を残していない（`BefoldApp/befold/App/SidebarHistoryController.swift:46-50`）。一方、プレビューがフォルダー一覧になるかは `fileListModel.selection` だけで決まる（`BefoldApp/befold/Viewer/PreviewTargetResolver.swift:47-63`）。復元時の選択は副作用頼みで、次の 3 経路すべてがフォルダー一覧に落ちうる。

- **A（本命・ドリルダウン）**: 同一ディレクトリ復元 `SidebarHistoryController.swift:74-77` は `matchingEntryURL(for:)` の結果をそのまま選択にするが、一覧に該当行が無いと生 URL が返る（`BefoldApp/befold/Viewer/FileListEntryIndex.swift:72-74`）。選択は非 nil だが索引に当たらず `PreviewTargetResolver.swift:57-59` で `.folder` に落ちる。この分岐は `refreshFileList()` を発行しないため `DirectoryLister.appendingOpenFile` の救済（`BefoldApp/befold/Viewer/DirectoryLister.swift:65-84`）も走らず、一覧が被さり続ける。
- **B（ツリー表示・親へ戻る）**: `dirChanged == true` 側は選択確定を一覧着地に委ねる（`SidebarHistoryController.swift:78-87`）が、着地側は既存のフォルダー選択が一覧内に残っていれば優先して保持する（`BefoldApp/befold/App/SidebarListingCoordinator.swift:88-96`）。履歴適用経路には「ファイルを選び直せ」という指示が無いため区別できない。さらに `SidebarHistoryController.swift:78` は `fileListModel.currentDirectory` へ直接代入しており、正規経路 `SidebarNavigator.moveCurrentDirectory`（`SidebarNavigator+FolderNavigation.swift:36-50`、TASK-465 で直接代入禁止と明記）を通らないため `discardExpansion()` 等がスキップされ、古い展開行が残って B を起こしやすくする。
- **C**: `SidebarHistoryController.swift:81-86` は「開いているファイルの親 ≠ 復元先ディレクトリ」でフォルダー行を選ぶが、`folderEntryURL` は `.folder` 行しか引かない（`FileListEntryIndex.swift:61-69`）ため nil になりやすく、`PreviewTargetResolver.swift:52` の guard でやはり `.folder` になる。

## 方針の候補

`HistoryEntry` に「提示対象（ファイル／フォルダー）」を持たせ、復元時に選択を一意に確定させる。実装着手前に `/review-design` を回すこと（状態を増やす変更のため）。

## テストの穴

`BefoldApp/befoldTests/ViewerWindowControllerHistoryTests.swift` の 4 ケースはファイル↔ファイルのみで、履歴がフォルダー提示を跨ぐケースが未カバー。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 履歴でフォルダー提示を通過した後に戻ってファイル提示のエントリへ到達すると、そのファイルがプレビューされる
- [ ] #2 上記が同一ディレクトリ内の戻り（原因 A）と親ディレクトリへの戻り（原因 B）の両方で成立する
- [ ] #3 履歴適用時のディレクトリ変更が SidebarNavigator.moveCurrentDirectory を通る（currentDirectory への直接代入をやめる）
- [ ] #4 ViewerWindowControllerHistoryTests に「フォルダー提示を跨ぐ戻り」の回帰テストを追加し、修正を戻すと落ちることを確認済み
<!-- AC:END -->
