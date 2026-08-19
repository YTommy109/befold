---
id: TASK-531
title: ウィンドウメニューに各ウィンドウの選択中タブだけを表示する
status: Done
assignee: []
created_date: '2026-08-19 13:54'
updated_date: '2026-08-19 13:55'
labels: []
dependencies: []
ordinal: 773000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ウィンドウメニューに全ウィンドウの全タブが 1 項目ずつ並んでしまう。AppKit は NSApp.windowsMenu の一覧を NSWindow 単位で自動生成するため、タブも別ウィンドウとして並ぶ。このメニューの目的はアクティブウィンドウの切り替えなので、各ウィンドウの選択中タブだけが並ぶのが妥当。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 タブを複数持つウィンドウは、選択中のタブ 1 件だけがウィンドウメニューに並ぶ
- [x] #2 タブを切り替えるとメニューの項目も追随して入れ替わる
- [x] #3 タブ化していないウィンドウとパネル類の表示は変わらない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AppKit の windowsMenu は NSWindow 単位の自動生成で、タブ選択を通知する仕組みが無い。新しい状態は足さず、tabGroup.selectedWindow をそのまま真とみなして isExcludedFromWindowsMenu を揃える方式にした。

- ViewerTabGrouping.isExcludedFromWindowsMenu(_:selectedTabOfGroup:): NSWindow 非依存の純粋判定
- ViewerTabGrouping.syncWindowsMenuMembership(among:): 渡されたウィンドウ群にだけ適用（パネル類を巻き込まないよう対象は呼び出し側が決める）
- ViewerWindowManager.syncWindowsMenuMembership(): allControllers のウィンドウを対象に委譲
- 呼び出し契機: ViewerWindowSessionSync.viewerWindowDidBecomeKey（タブ選択は必ずキー化を伴う）と SessionRestorer.restoreTabGroup 末尾（背面グループはキーにならないため）

検証: swift test 1667 件成功。syncWindowsMenuMembership の本体を潰すと新規テストが 2 件落ちることを確認済み。swiftlint は main と同じ 54 件（新規ゼロ）。
<!-- SECTION:NOTES:END -->
