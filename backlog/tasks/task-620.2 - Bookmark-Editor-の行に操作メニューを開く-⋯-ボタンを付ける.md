---
id: TASK-620.2
title: Bookmark Editor の行に操作メニューを開く ⋯ ボタンを付ける
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 11:42'
updated_date: '2026-09-13 13:09'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 812000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
管理パネルの行の操作（ブックマーク行: 別名・フォルダーへ移動・削除、フォルダー行: 改名・新規フォルダー・削除）は右クリックの `contextMenu` にしか無く、使う人がその存在に気づけない。サイドバーのヘッダー右端にある ⋯（`SidebarHeaderControls` の overflow、`ellipsis.circle`）のように、目に見える入口を置きたい。

右クリックメニューは残す（慣れた人の近道として）。2 つの入口の中身が別々に定義されると片方だけ項目が増える・並びがずれる形で割れるので、同じ定義から作ること（CLAUDE.md「決めたことには、破れたら落ちるものを付ける」）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ブックマーク行とフォルダー行の右端に ⋯ ボタンがあり、クリックで操作メニューが開く
- [x] #2 ⋯ から開くメニューと右クリックメニューの項目・並び・有効/無効が一致する
- [x] #3 ⋯ ボタンのクリックで行の選択・ダブルクリックで開く動作が誤って起きない
- [x] #4 ⋯ ボタンに VoiceOver で読み上げられるラベルと help が付いている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 行の操作を @ViewBuilder の bookmarkActions / folderActions に切り出し、contextMenu と ⋯ の Menu の両方から呼ぶ（入口ごとに項目を書かない構造で一致を担保）
2. ⋯ は borderless の Menu（SidebarHeaderControls の overflow と同じ modifier 群）。読み上げ名・help は l10n キー bookmarks.manager.bookmarkActions / folderActions
3. ダブルクリックで開く gesture を ⋯ を除いた行本体だけに付け直す
4. 実機で、項目・並び・有効/無効の一致、⋯ で選択されない・開かないこと、AX のラベルと help を測る
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 2 つの入口の一致は「同じ関数を呼ぶ」構造で担保した（SwiftUI の View は単体テストの対象外のため、テストではなく破りようのない構造を選んだ）。状態も経路も増やさない 1 ファイル内の変更なので /review-design は対象外と判断。
実機（.tmp/TASK-620/6202-*.png、CGEvent でクリック）:
- ⋯ クリックでメニューが開く。ブックマーク行 = Set Alias… / Move to Folder / Remove Bookmark、フォルダー行 = Rename Folder… / New Folder… / Delete Folder で、右クリックと項目・並びが一致。Move to Folder のサブメニューはどちらの入口でも Top Level が無効・Sample が有効（ルート直下の diagram.mmd）
- ⋯ のクリック後も行は選択されない。⋯ のダブルクリックでは窓が開かない（対照: 行の文字部分のダブルクリックでは diagram.mmd が開くことを同じ手段で確認）
- アクセシビリティ（AXUIElement で直接読んだ値）: ブックマーク行の ⋯ は AXMenuButton / 名前 Bookmark Actions / help Bookmark Actions。フォルダー行は DisclosureGroup がラベルを 1 要素にまとめるため、⋯ の名前がフォルダー名（例 Sample）になり help は Folder Actions。Label 側 .accessibilityElement(children: .combine) では不変、HStack に .contain では AXHeading に吸収され ⋯ が AX ツリーから消え、.accessibilityActions はカスタム操作として現れなかった（AXCustomActions が空）ため、いずれも採らなかった。「Sample、メニューボタン」+ help で意味は通るので受け入れた
accessibility-reviewer: 要対応なし。任意 (a) ラベルの二重付与 → .accessibilityLabel を外し Label + iconOnly に一本化 (b) フォルダー行の .accessibilityActions → 上記の実測で効かず不採用 (c) キーボードだけで ⋯ / 別名・移動・改名・開く に届かない → 変更前からある問題で本タスクの範囲外。別タスク化をユーザーに相談する
検証: swift test --skip Integration --skip FileWatcherTests 1933 件パス（UI 修飾子のみの後段の変更は xcodebuild のビルドで確認）/ swiftlint 差分ゼロ / 型グループ BookmarkManagerView 332 行（閾値内）/ l10n は en・ja 両方を追加
native-app-design.md: BookmarkManagerView の行に 2 つの入口と共通の @ViewBuilder を追記
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブックマーク行とフォルダー行の右端に ⋯ を置き、右クリックと同じ @ViewBuilder から操作メニューを開けるようにした（項目・並び・有効/無効の一致を構造で担保）。ダブルクリックで開く範囲から ⋯ を外した。実機で両入口のメニュー一致、⋯ で選択・オープンが起きないこと、AX のラベルと help を確認。フォルダー行の ⋯ は DisclosureGroup の仕様でフォルダー名で読まれる（help は Folder Actions）ことを実測して記録。
<!-- SECTION:FINAL_SUMMARY:END -->
