---
id: TASK-82
title: パス無し CLI オプション転送が既存インスタンス側で無視される（表示行番号/ソース/プレビュー/ソート順）
status: Done
assignee: []
created_date: '2026-07-21 05:46'
updated_date: '2026-07-21 06:06'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/AppDelegate.swift
priority: high
type: bug
ordinal: 67000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppDelegate.launch() は task-73.7 の修正で !paths.isEmpty ガードを外し、パス無しの CLI オプションフラグ（--line-numbers/--source/--preview/--sort 等）も既存インスタンスへ forward() するようになった。
しかし受信側の openPaths(_:options:) は、paths が空のときは setHiddenFiles(...) のみを呼び、showLineNumbers/sourceMode/sortOrder は for path in paths ループの中でのみ各ウィンドウへ適用される。paths が空の場合このループは一度も実行されないため、これらのオプションは既存ウィンドウへ一切反映されない。
修正前（このパスが常に新規 AppDelegate/NSApplication インスタンスを起動していた頃）は restoreLastSession(options:) が復元される全ウィンドウへ showLineNumbersOverride 等を適用していたため、これは動作の退行である。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 既存インスタンスが起動中の状態で 'befold --line-numbers'（パス無し）を実行すると、転送先の既存ウィンドウに行番号表示が反映される
- [x] #2 source/preview/sort 等、他のパス無しオプションについても同様に既存ウィンドウへ反映される
- [x] #3 パス無し転送時のオプション適用を検証する自動テストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: 新規状態やパスは追加せず、既存のViewerWindowManagerが持つ「開いている全ウィンドウへ一括反映する」既存パターン(setHiddenFiles/toggleHiddenFiles→refreshAllSidebars)に倣い、新規ヘルパー applyDisplayOverrides(showLineNumbers:sourceMode:sortOrder:) を追加して開いている全controllerへ適用する。\n2. AppDelegate.openPaths で paths.isEmpty の場合にこのヘルパーを呼ぶよう分岐を追加(既存のfor pathループはそのまま)。\n3. 各オプションは既存の適用APIを再利用: store.applyShowLineNumbersOverride / controller.setSourceMode / controller.fileListModel.sortOrder への代入。\n4. ViewerWindowManagerDisplayOverridesTests.swiftを新設しTDDでテスト(全ウィンドウへ反映/nilは変更しない)を追加。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。ViewerWindowManager.applyDisplayOverrides を追加し、AppDelegate.openPaths のpaths.isEmpty分岐から呼び出すよう変更。新規テスト2件(ViewerWindowManagerDisplayOverridesTests.swift)含め全543テストgreen。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowManager.applyDisplayOverrides(showLineNumbers:sourceMode:sortOrder:) を追加し、開いている全ウィンドウへ既存API(store.applyShowLineNumbersOverride/controller.setSourceMode/fileListModel.sortOrder)経由でオプションを適用するようにした。AppDelegate.openPaths がpaths.isEmptyの場合にこれを呼ぶよう変更(showHiddenFilesの既存扱いは維持)。検証: ViewerWindowManagerDisplayOverridesTests.swiftを新設し、全ウィンドウへ反映されること・nil指定時は既存状態を変更しないことを確認する2テストを追加、green。プロジェクト全543テストgreen。
<!-- SECTION:FINAL_SUMMARY:END -->
