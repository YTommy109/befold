---
id: TASK-445
title: Quick Open で別フォルダのファイルを選ぶと、フォルダーだけ移動して本文が切り替わらないことがある
status: To Do
assignee: []
created_date: '2026-08-11 08:17'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 673000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 症状（ユーザー報告）

Quick Open（cmd+p）で選んだファイルが開かないことがある。サイドバーのフォルダーは選んだファイルのフォルダーへ移動するのに、ビューア本文が切り替わらない。現在表示中のファイルとは**異なるフォルダー**のファイルを選んだときに起きているように見える。

## 現時点で分かっていること（静的調査のみ。再現・実測は未実施）

決定からオープンまでの経路:

1. `QuickOpenModel.commitSelection()`（BefoldApp/befold/App/QuickOpenModel.swift:113-117）— `await environment.resolveFileToOpen` を挟んでから `onOpen`
2. `QuickOpenPanelController.present()` 内のクロージャ（QuickOpenPanelController.swift:70-73）— `dismiss()` してから `onOpen(url)`
3. `AppDelegate.openFromQuickOpen(_:)`（AppDelegate.swift:447-453）— `activeViewerController` があれば `switchFile(to:)`、無ければ `openViewer(for:)`
4. `ViewerWindowController.switchFile(to:)`（ViewerWindowController+FileNavigation.swift:36-46）→ `performFileSwitch`（:55-73）で `store.openFile(newURL)` → 成功時のみ `sidebar.syncAfterSwitch(to:)`
5. `SidebarNavigator.syncAfterSwitch(to:)`（SidebarNavigator.swift:349-358）でフォルダー移動

本文の読み込み（`ViewerStore.openFile` → `loadContent`、ViewerStore.swift:247-264 / 343-368）は世代ガード付きの非同期。フォルダー移動（`refreshFileList` → `performListing`、SidebarNavigator.swift:197-219 / 240-280）は別タスクの非同期。**2 つは別々の非同期経路**で、症状は「後者だけ成功し前者が反映されない」形に一致する。

## 未確認の疑い（着手時にここから潰す）

- **A. `activeViewerController` が `NSApp.mainWindow` 依存**（AppDelegate.swift:237-239）。Quick Open パネルは `.nonactivatingPanel` の borderless panel（main にはならない想定）だが、`dismiss()` 直後に `NSApp.mainWindow` が nil を返す瞬間があると `openViewer(for:)` 側へ落ち、期待と違うウィンドウ挙動になりうる。
- **B. `syncAfterSwitch` の分岐が非対称**（SidebarNavigator.swift:349-358）。同一フォルダー分岐は `fileListModel.selection` を同期的に確定するが、別フォルダー分岐は確定せず非同期の `refreshFileList` 着地に委ねる。症状が「別フォルダーのときだけ」である報告と分岐が一致する。
- **C. `commitSelection()` の await 中に候補配列が差し替わりうる**（QuickOpenModel.swift:113-117。URL はキャプチャ済みのため誤ファイルを開くことは無いが、確定タイミングの競合は残る）。

再現条件（フォルダー階層・ツリー表示 ON/OFF・絞り込みの有無・毎回か時々か）が特定できていないため、まず再現から入ること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 別フォルダーのファイルを Quick Open で選んだときに本文が切り替わらない事象を再現でき、原因を実測（ログまたは失敗するテスト）で特定できている
- [ ] #2 原因を修正し、別フォルダー・同一フォルダーのいずれのファイルを Quick Open で確定しても、サイドバーのフォルダー移動と本文の切り替えが必ず両方反映される
- [ ] #3 syncAfterSwitch の同一フォルダー分岐と別フォルダー分岐で、選択確定の扱いが非対称なまま残らない（統一するか、非対称である理由を doc コメントで明示する）
- [ ] #4 修正した経路を破ると落ちるユニットテストがある（Quick Open 確定 → 別フォルダーのファイルが ViewerStore に読み込まれることを検証する）
<!-- AC:END -->
