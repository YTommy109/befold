---
id: TASK-119
title: CLI オプションでサイドバーの表示/非表示を指定できるようにする
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-24 04:38'
updated_date: '2026-07-24 05:06'
labels:
  - cli
  - feature
dependencies: []
priority: medium
ordinal: 105000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
起動時の CLI オプションでサイドバーのオン/オフを指定できるようにする。既存の表示オプション(--hidden-files / --sort / --line-numbers / --source など)と同様に、指定が無ければ保存済み設定・既定値を維持する。CLIOpenOptions / OpenCLIOptions / CLIInstanceRouter の転送・復元、および GUI 側の適用まで一貫して反映する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバー表示/非表示を指定する CLI オプションが --help に表示される
- [x] #2 オプション指定に応じて起動したウィンドウのサイドバーが開いた/閉じた状態になる
- [x] #3 オプション未指定時は既存の保存済みサイドバー状態・既定値を維持する
- [x] #4 パス無し指定・既存インスタンスへの転送でも同様に反映される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIOpenOptions に showSidebar: Bool? を追加
2. OpenCLIOptions に SidebarVisibilityFlag(EnumerableFlag, --sidebar/--no-sidebar)を追加し3値変換
3. CLIInstanceRouter(BefoldCLI) forward/decode に showSidebar を追加
4. ViewerSplitViewController に SidebarCollapsible プロトコル + setSidebarCollapsed(既存 toggleSidebar 経路を再利用)
5. ViewerWindowController に split controller 参照保持 + setSidebarCollapsed(_:) 公開
6. ViewerWindowManager.openViewer に sidebarVisibleOverride、applyDisplayOverrides に showSidebar
7. AppDelegate.openViewer(for:options:)/openPaths、SessionRestorer.openViewer で showSidebar を転送
8. テスト: parse(--sidebar/--no-sidebar)、排他、decode ラウンドトリップ、help 表示
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLI に --sidebar/--no-sidebar を追加(EnumerableFlag で排他)。CLIOpenOptions.showSidebar(Bool?) を新設し、CLIInstanceRouter の forward/decode で転送・復元、GUI では ViewerWindowManager.openViewer(sidebarVisibleOverride:)/applyDisplayOverrides(showSidebar:)、AppDelegate.openPaths、SessionRestorer 経由で新規・既存ウィンドウ双方へ適用。既存ウィンドウへの適用は ViewerSplitViewController の toggleSidebar 経路を再利用する SidebarCollapsible.setSidebarCollapsed で実現。未指定時は nil で保存済み状態を維持。--help 表示・排他・decode ラウンドトリップ・新規/既存ウィンドウ開閉を swift test(577件全通過)で検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
