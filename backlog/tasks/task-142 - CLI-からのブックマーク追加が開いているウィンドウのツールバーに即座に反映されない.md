---
id: TASK-142
title: CLI からのブックマーク追加が開いているウィンドウのツールバーに即座に反映されない
status: To Do
assignee: []
created_date: '2026-07-25 04:07'
updated_date: '2026-07-25 04:07'
labels:
  - ui
  - cli
dependencies: []
priority: low
ordinal: 218000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-127 で `befold --bookmark <path>` は起動中の GUI へ転送されるようになり、GUI プロセスの BookmarkStore に即座に追加されるようになった。しかし、対象ファイルを表示中のウィンドウがある場合、ツールバーのブックマークアイコン(bookmark / bookmark.fill)は更新されない。

ViewerToolbarController.updateBookmarkToolbarItem() が呼ばれるのは、ユーザー自身のトグル操作時・store.onContentReloaded 時・アイテム生成時のみで(ViewerWindowController.swift:209, ViewerToolbarController.swift:120-134, 278)、外部からブックマークが増減したときに全ウィンドウへ通知する経路が無いため。File > Bookmarks メニューは開くたびに読み直すので影響を受けない。

TASK-127 以前から存在する挙動だが、CLI からの追加が GUI プロセスへ届くようになったことで再現しやすくなった。

対応案: BookmarkStore の変更を購読可能にする(@Observable 化 or 変更通知)か、AppDelegate の CLI ブックマーク処理から ViewerWindowManager 経由で全ウィンドウの updateBookmarkToolbarItem() を呼ぶ。前者はストア側に責務が寄るが購読者が増えても破綻しない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLI からブックマークが追加された対象ファイルを表示中のウィンドウで、ツールバーのアイコンが再読込を待たずに反映される
- [ ] #2 反映経路にテストがある(全ウィンドウへの更新が呼ばれること、または変更通知の購読)
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
関連: TASK-136(ViewerToolbarController のツールバー状態同期を単一化する)と同じ箇所に触れる。先に TASK-136 を進める場合は、その単一化した同期経路に外部変更の反映を載せるほうが安上がり。
<!-- SECTION:NOTES:END -->
