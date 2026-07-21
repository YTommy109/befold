---
id: TASK-87
title: CLI転送で--sort指定してもサイドバー表示が更新されない(applyDisplayOverridesがrefreshFileListを呼ばない)
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 07:21'
updated_date: '2026-07-21 08:27'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowManager.swift
priority: high
type: bug
ordinal: 72000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既に起動中のインスタンスへ CLI から `--sort` オプションを転送すると、ViewerWindowManager.applyDisplayOverrides() が対象ウィンドウの fileListModel.sortOrder を直接更新するが、sidebar.refreshFileList() を呼んでいない。
一方、UI 側のソート切り替えハンドラ(FileListView の onSortOrderChanged, ViewerWindowController.swift:245-249)は sortOrder 更新と refreshFileList() を必ずセットで呼んでいる。
結果として、ウィンドウが既に開いている状態で `befold --sort alphabetical` を実行すると、ソート順の表示(トグルボタンのアイコン/ツールチップ)は alphabetical に切り替わるのに、サイドバーに表示されているファイル一覧の並び順は古いソート順のまま変わらない。既存の ViewerWindowManagerDisplayOverridesTests は sortOrder の値のみを検証しており、entries の並び替えは検証していない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLI転送でsortOrderが更新された際、既に開いているウィンドウのサイドバーのentriesも新しいソート順で再表示される
- [x] #2 applyDisplayOverridesがsortOrderを更新するパスと、UIのソート切り替えハンドラが同じrefreshFileList()呼び出しパターンに揃っている
- [x] #3 sortOrder変更後にentriesの並び順が実際に更新されることを検証するテストが追加されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ViewerWindowManager.applyDisplayOverrides()のsortOrder分岐に controller.sidebar.refreshFileList() を追加し、UIのソート切り替えハンドラ(ViewerWindowController.swift onSortOrderChanged)と同じ呼び出しパターンに揃えた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowManager.swift:66付近のapplyDisplayOverridesで、CLI転送によるsortOrder更新後にsidebar.refreshFileList()を呼ぶよう修正。新規テストapplyDisplayOverridesRefreshesSidebarEntries(ViewerWindowManagerDisplayOverridesTests.swift)で、foldersFirst→alphabetical切替時にentriesの並び順(kind配列)が実際に再取得・反映されることを検証。swift test で559件全green(既存テストへの回帰なし)。
<!-- SECTION:FINAL_SUMMARY:END -->
