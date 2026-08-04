---
id: TASK-142
title: CLI からのブックマーク追加が開いているウィンドウのツールバーに即座に反映されない
status: Done
assignee:
  - '@claude'
created_date: '2026-07-25 04:07'
updated_date: '2026-07-25 04:37'
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
- [x] #1 CLI からブックマークが追加された対象ファイルを表示中のウィンドウで、ツールバーのアイコンが再読込を待たずに反映される
- [x] #2 反映経路にテストがある(全ウィンドウへの更新が呼ばれること、または変更通知の購読)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 単純化検討: BookmarkStore(BefoldKit の純粋ロジック)へ購読機構を足すのではなく、bookmarkStore とウィンドウ登録簿の両方を既に持つ ViewerWindowManager に処理を寄せ、既存の setHiddenFiles -> refreshAllSidebars と同じ「値を変える + 全ウィンドウへ反映」の形に揃える。新しい状態も通知機構も増えず、AppDelegate は転送のみになる。TASK-136 で導入した refreshToolbarState() をそのまま利用する。
1. テスト先行: MockedViewerWindowManager に隔離 defaults の bookmarkStore を追加し、manager.addBookmarks(for:) が (a) BookmarkStore へ追加し (b) 開いているウィンドウのツールバーアイコンへ即反映することを検証する
2. 実装: ViewerWindowManager に addBookmarks(for urls:) と refreshAllToolbars() を追加し、AppDelegate.handleCLIOpenRequest の .bookmark 分岐を windowManager.addBookmarks(for:) へ差し替える
3. swift build / swift test / jest で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
関連: TASK-136(ViewerToolbarController のツールバー状態同期を単一化する)と同じ箇所に触れる。先に TASK-136 を進める場合は、その単一化した同期経路に外部変更の反映を載せるほうが安上がり。

単純化検討の結果、BookmarkStore(BefoldKit)へ購読機構を足す案は採らず、bookmarkStore とウィンドウ登録簿の両方を既に持つ ViewerWindowManager に addBookmarks(for:) を新設して、既存の setHiddenFiles -> refreshAllSidebars と同じ「値を変える + 全ウィンドウへ反映」の形へ揃えた。新しい状態・通知機構は増えず、AppDelegate の .bookmark 分岐は転送 1 行になった。反映自体は TASK-136 で導入した refreshToolbarState() をそのまま使う(ブックマーク状態はツールバーが表示のたびに読み直すため、差分通知は不要)。

副産物: MockedViewerWindowManager が bookmarkStore を注入していなかったため本番 UserDefaults の BookmarkStore が使われていた。隔離 defaults の BookmarkStore を明示注入するよう修正。

検証: swift build ok / swift test 635 tests 全通過 / npx jest 266 PASS / webview-smoke PASS。新規テスト ViewerWindowManagerBookmarkTests は追加時点でコンパイル失敗(RED)を確認し、addBookmarks から refreshAllToolbars() 呼び出しを取り除く変異でツールバー反映テストが失敗することも確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI からのブックマーク追加を ViewerWindowManager.addBookmarks(for:) へ集約し、追加後に開いている全ウィンドウのツールバーを refreshToolbarState() で再同期するようにした。表示中ファイルのブックマークアイコンが再読込を待たず反映される。BookmarkStore へ購読機構を足す代わりに既存の setHiddenFiles -> refreshAllSidebars と同型の fan-out に揃えたため、新しい状態は増えていない。ViewerWindowManagerBookmarkTests(実アイテムの tint を検証、変異注入で検知力を確認)を追加し、swift test 635 / jest 266 / webview-smoke が通過。
<!-- SECTION:FINAL_SUMMARY:END -->
