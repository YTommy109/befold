---
id: TASK-593.2
title: 窓種別 .slide と「スライドモードで開く」を追加する
status: To Do
assignee: []
created_date: '2026-09-06 09:25'
labels:
  - sidebar
  - slide-mode
dependencies:
  - TASK-593.1
documentation:
  - docs/superpowers/specs/2026-09-06-slide-window-design.md
parent_task_id: TASK-593
priority: medium
type: feature
ordinal: 860000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スライド窓の器を作る。既存のビューア窓に生成時の窓種別 `kind`（`.viewer` / `.slide`）を足し、`.slide` のときはアセンブラがツールバー無し・サイドバー折りたたみ固定・`tabbingMode = .disallowed` で組む。前後移動キーは次のサブタスクで、ここでは「サイドバーの無い窓が開いて閉じられる」までを作る。

入口はサイドバーのコンテキストメニューだけ。`SidebarContextMenu.openElsewhereEntries` の表に 1 行足し、`OpenDisposition` に `.slide` を加える（delegate メソッドは増やさない）。フォルダー行は「新しいウィンドウで開く」と同じく最初の対応ファイルを開く。`openViewer` は `.slide` を `.newWindow` と同じ「常に新規窓」の規則で扱う。

サイドバーを開かせないガードは 3 箇所（`ViewerMenuValidator` で ⌘S と ⌘← を無効、`ViewerSplitViewController.toggleSidebar(_:)` を `.slide` で no-op、ツールバー自体を付けない）。1 箇所でも漏れると「サイドバーの無い窓」が崩れるので、3 経路すべてで `isCollapsed` が変わらないことをテストで固定する。折りたたみは種別の帰結であって利用者の選択ではないので `SidebarStateStore.recordToggle` に書かない（ADR 0002）。

一覧の初期値は元の窓から引き継ぐ。`SidebarListingSeed` は directory / listing / sortOrder / showHiddenFiles の 4 つしか運ばない（実測）ので、レイアウト・「変更のみ」・ツリーの展開状態を足し、`canApply(to:)` の一致条件も広げる。この拡張は「新しいウィンドウで開く」にも同じ引き継ぎをもたらす（意図した副作用）。展開状態を `FileListModel` がどの形で持っているかは未確認で、着手時に決める。

セッション復元は `ViewerTabGrouping.tabGroup(of:)` のスナップショットから `.slide` の窓を除外する（`SessionLayout` に種別は足さない）。

l10n: `sidebar.context.openInSlideMode`（en / ja）を `sidebar.context.openInNewWindow` の隣に置く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コンテキストメニューの「スライドモードで開く」で、選んだファイル（フォルダー行なら最初の対応ファイル）がサイドバー無し・ツールバー無しの新しい窓で開く
- [ ] #2 スライド窓は「タブを好む」設定でも既存窓のタブに合流せず、⌘W で閉じられる
- [ ] #3 スライド窓で ⌘S・⌘←・`toggleSidebar(_:)` のどれを通してもサイドバーが開かず、`SidebarStateStore` に書き込みが起きないことをテストが固定している
- [ ] #4 スライド窓の隠れた一覧が元の窓の並び順・不可視・変更のみ・レイアウト・ツリーの展開状態を引き継いでいる（`SidebarListingSeed` のテスト）
- [ ] #5 再起動後のセッション復元にスライド窓が含まれない（スナップショットのテスト）
- [ ] #6 ソース表示・差分表示（⌘1/⌘2/⌘3・⌘U・⌘\）がスライド窓でも従来どおり効く
- [ ] #7 `/l10n-check` が通る
<!-- AC:END -->
