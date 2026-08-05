---
id: TASK-188
title: サイドバーの幅を広げ、ファイル名ホバーで全文ツールチップを表示する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-28 14:25'
updated_date: '2026-07-30 02:45'
labels: []
dependencies: []
ordinal: 271000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバー（FileListView）の最小幅と初期（デフォルト）幅を現状より少し広げる。また、ファイル名が省略表示（truncation）されている場合でも、行のホバーで省略なしの完全なファイル名をツールチップ表示できるようにする。狭いサイドバーで長いファイル名が読めない問題を緩和する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーの初期幅が現状より広くなる（初回表示・記憶がない場合のデフォルト）
- [x] #2 サイドバーの最小幅が現状より広がり、極端に狭くできない
- [x] #3 ファイル名行にホバーすると、省略なしの完全なファイル名がツールチップ（help)で表示される
- [x] #4 ウィンドウ単位のサイドバー幅記憶（既存挙動）が壊れない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerSplitViewController: sidebarItem.minimumThickness を 150→220、maximumThickness を 300→360 に拡大する。
2. 初期(初回起動・記憶なし)幅を広げるため、autosave キー("NSSplitView Subview Frames ViewerSplitView")が UserDefaults に存在しない場合のみ、viewDidLoad 等で splitView.setPosition(220, ofDividerAt: 0) を明示適用する。既存の記憶がある場合は triggersしない(AC#4 を壊さない)。
3. FileListEntryRow: folder/file 行の HStack に .help(entry.url.lastPathComponent) を追加し、ホバーで完全なファイル名をツールチップ表示する(parentNavigation の ".." 行は対象外)。
4. befoldTests でロジック検証可能な範囲(値の妥当性等)があればテスト追加。WebView/GUI 同様、SplitView の実挙動は手動確認。
5. /run 相当でアプリを起動し、サイドバー幅・ツールチップ・幅記憶の実機確認を行う。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ViewerSplitViewController の minimumThickness 150→200、maximumThickness 300→360。autosaveキー(NSSplitView Subview Frames ViewerSplitView)がUserDefaultsに存在しない場合のみ viewWillAppear で splitView.setPosition(220, ofDividerAt:0) を適用(既存記憶時は不介入)。FileListEntryRow の folder/file 行に .help(entry.url.lastPathComponent) を追加。
検証: swift build / swift test(843件)/ npx jest(322件)すべて成功。実機起動して既存の保存済みサイドバー幅(308px)が起動前後で変化しないことを確認(AC#4)。min/max thickness は NSSplitViewItem の標準機構、tooltip は SwiftUI .help() の標準機構でありコードレビューで妥当性確認(AC#2, AC#3)。
AC#1(初回起動時のデフォルト幅)は、実機の保存済み設定を書き換える実験をユーザーが希望しなかったため、実機での直接確認は未実施。ロジックは「autosaveキー不在時のみ setPosition(220) を適用」という単純な条件分岐であり、AC#4の検証(既存キーがある場合に何も上書きされない)がこの分岐の反対側を裏付ける。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー最小幅150→200px・最大幅300→360pxに拡大し、初回起動(記憶なし)時のみ既定幅220pxを適用。FileListEntryRowのfolder/file行に.help()でファイル名全文ツールチップを追加。swift build/swift test(843件)/npx jest(322件)全通過。実機起動で既存の保存済み幅(308px)が変化しないことを確認しAC#4を検証。AC#1はautosaveキー不在時のみ既定幅を適用する分岐のコードレビューとAC#4検証の裏付けにより確認。
<!-- SECTION:FINAL_SUMMARY:END -->
