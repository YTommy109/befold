---
id: TASK-61
title: フォルダー選択時にプレビューエリアへフォルダー一覧を表示する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-18 10:29'
updated_date: '2026-07-19 08:12'
labels: []
dependencies: []
documentation:
  - docs/superpowers/specs/2026-07-18-folder-preview-listing-design.md
  - docs/superpowers/plans/2026-07-18-folder-preview-listing.md
priority: medium
ordinal: 300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーでフォルダーを選択しても、プレビューエリアは直前に開いていたファイルの内容を表示し続けており、フォルダーの中身を確認できない。設計は docs/superpowers/specs/2026-07-18-folder-preview-listing-design.md に、実装計画は docs/superpowers/plans/2026-07-18-folder-preview-listing.md にレビュー・承認済みで存在する。実装はこのプランに従って進める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーでフォルダーをシングルクリックで選択すると、プレビューエリアにそのフォルダー直下の一覧(フォルダー優先+名前順)が表示される
- [x] #2 一覧の並び順・隠しファイル表示はサイドバーの現在の設定に従い、独自の固定値を持たない
- [x] #3 一覧内の非対応ファイルの見た目・クリック時の扱いはサイドバーと同じ基準になる(除外・無効化はしない)
- [x] #4 一覧内はシングルクリックで選択のみ、ダブルクリックでファイルを開く/サブフォルダーへ移動する
- [x] #5 一覧内でのダブルクリックによる移動・オープンはサイドバー側の表示(選択ハイライト・カレントディレクトリ)にも反映される
- [x] #6 フォルダーへダブルクリックで移動した際、最初のファイルを自動的に開く既存の挙動が廃止され、移動後は新しいフォルダーの一覧が表示される
- [x] #7 戻る操作は既存の「..」行を使い、新規ナビゲーションUIは追加しない
- [x] #8 zip アーカイブの中身表示は本タスクのスコープに含めない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。5タスク+2レビュー起因の修正コミット(計7コミット)。全448自動テストPASS、swiftlint新規/変更ファイルにlint違反なし、xcodebuild成功。手動確認(実アプリ)で全AC(1-8)をユーザーが直接確認: フォルダー単クリックでの一覧表示・フォルダー優先名前順・非対応ファイルのグレー表示と選択可・単クリック選択のみ/ダブルクリックで開く移動・サイドバーとの選択/カレントディレクトリ同期・自動オープン廃止・「..」での戻る・zipスコープ外(未変更)。最終全体レビュー(Opus)でAC2の結合バグ(FolderListingViewの.taskキーがdirectoryのみで並び順/隠しファイル変更に追従しない)を検出、ListingKey複合キーで修正・再レビューでReady to merge: Yes確認。手動再確認時に2件の見かけ上のバグ(/tmp配下のサンドボックス制限によるダブルクリック移動不可、openコマンドがビルド前の旧プロセスを再利用したことによる不可視設定トグル未反映)が出たが、いずれもテスト環境起因の偽陽性と判明し、実装には問題なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーでフォルダーを選択した際、プレビューエリアにそのフォルダー直下の一覧を表示する機能を実装。PreviewTargetResolver(選択→表示対象の純粋関数)、FileListEntryRow(サイドバーと共有する行表示)、FolderListingView(新規プレビュー用一覧、隠しファイル/並び順の変更に追従)を新設し、ViewerContentView/ViewerWindowControllerに配線。あわせてSidebarNavigator.navigateToFolderの「移動時に最初のファイルを自動的に開く」挙動を廃止。全448自動テストPASS、xcodebuild成功、swiftlintクリーン、実アプリでの手動確認によりAC1-8をすべて確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
