---
id: TASK-593.1
title: 旧サイドバー内スライドモードを撤去する
status: To Do
assignee: []
created_date: '2026-09-06 09:25'
labels:
  - sidebar
  - slide-mode
dependencies: []
documentation:
  - docs/superpowers/specs/2026-09-06-slide-window-design.md
parent_task_id: TASK-593
priority: medium
type: chore
ordinal: 859000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
新しいスライド窓を足す前に、TASK-585 / 587 で入れたサイドバー内スライドモードを撤去する。先に消すのは、2 つの「スライドモード」が同時に存在する期間を作らないため（l10n キー `menu.view.slideMode` の意味が変わる、View メニューとコンテキストメニューに別物が並ぶ）。

撤去対象は spec の「旧モードの撤去」節に列挙してある: `SlideModeCoordinator`、`SidebarSlideMetrics`、`SidebarTransientState.isSlideMode` / `setSlideMode(_:)`、`ViewerSplitViewController.setSlideMode(_:)` と `thicknessBeforeSlideMode` / `setAutosaveEnabled(_:)`、`SidebarCollapsible.setSlideMode`、`FileListView` の `.redacted(reason:)`、`SidebarHeaderView` の解除アイコン分岐、`MainMenuBuilder+ViewMenu.swift` の項目、`ViewerWindowController.toggleSlideMode(_:)` / `isSlideMode`、`ViewerMenuValidator` の分岐、`ViewerWindowAssembler.makeSidebarDidHide` のスライド解除、`SidebarDisplayRequest.slideMode`、xcstrings の `menu.view.slideMode` / `sidebar.slideMode.exit`、native-app-design.md の該当行。

`SidebarDisplayRequest` が `.display` だけになるなら列挙ごと畳み、`fileListDidRequestDisplayChange` は `SidebarDisplayChange` を直接受ける形にしてよい（TASK-586 で `.slideMode` を `SidebarDisplayChange` に混ぜなかった理由は幅の面倒を見せないためで、撤去後は理由ごと消える）。

TASK-588 / 589 は対象が消えるので、このタスクの完了時に「見送り（旧モード撤去により対象消滅）」の Final Summary を付けて Done にする。TASK-590 / 591 / 592 は `.slideMode` を前提にした記述を持つので Description / AC を実態に合わせて書き換える。

TASK-585 の Implementation Notes にある「幅 480 への上限拡大」はスライドモードと独立した変更なので残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 上記の旧シンボルが `rg` で 0 件で、swift build / swift test / xcodebuild が通る
- [ ] #2 View メニューにスライドモードの項目が無く、サイドバーヘッダーに解除アイコンの分岐が無い
- [ ] #3 `/l10n-check` が通り、`menu.view.slideMode` と `sidebar.slideMode.exit` が xcstrings から消えている
- [ ] #4 サイドバー幅の上限 480 と `ViewerSplitViewController` の autosave の挙動は変わっていない（既存テストが通る）
- [ ] #5 TASK-588 / 589 が見送りの要約付きで Done になり、TASK-590 / 591 / 592 の Description と AC から `.slideMode` の前提が消えている
- [ ] #6 native-app-design.md の SidebarSlideMetrics / SlideModeCoordinator / SidebarTransientState の記述が撤去後の実態に合っている
<!-- AC:END -->
