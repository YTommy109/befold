---
id: TASK-706
title: プレビュー内のフォルダー一覧のヘッダーに項目数(ファイル+フォルダー)を表示する
status: Done
assignee: []
created_date: '2026-10-14 04:31'
updated_date: '2026-10-14 13:43'
labels:
  - sidebar
  - folder-list
dependencies: []
priority: low
type: feature
ordinal: 895000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
フォルダーを選んだときにコンテンツエリアへ出る一覧(FolderListingView)は、そのフォルダーに何件あるかが分からない。ヘッダー情報として直下の項目数(ファイルとフォルダーの合計)を出したい(利用者要望)。**対象はコンテンツエリアの一覧のみで、サイドバーは現状のまま変えない。** 着手前に決める点: 数える対象(隠しファイル・非対応形式・git 変更のみ表示などの絞り込みが効いているとき、見えている件数か実数か)。FolderListingView は FolderListingSourceResolver によりサイドバーの揃えた一覧を使う場合と自前で列挙する場合があるので、どちらの経路でも同じ件数規則になること。実装前に /review-design を回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダーを選ぶと、コンテンツエリアの一覧のヘッダーに直下の項目数(ファイルとフォルダーの合計)が表示される
- [x] #2 サイドバーの表示・挙動は変わらない
- [x] #3 絞り込み・隠しファイル表示の切替時に、件数が何を数えているか(見えている件数か実数か)が決まっており、その決定が doc コメントかテストで固定されている
- [x] #4 サイドバーの一覧を使う経路と自前で列挙する経路(FolderListingSourceResolver)の両方で、同じ規則の件数が出る
- [x] #5 列挙に失敗したフォルダーでは 0 件と区別できる表示になる
- [x] #6 表示文字列は Localizable.xcstrings に en/ja で追加され、1 件・複数件の複数形が崩れない
- [x] #7 ディレクトリ監視は無いため、ウィンドウがキーに戻ったとき(サイドバーの再取得と同じ契機)に件数が取り直される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 件数は displayedEntries(見えている行)を数える。両供給元が合流するので同じ規則(AC4)。2. 列挙失敗は既存の folder.enumerationFailed を出す。3. 複数形は xcstrings の plural variations。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決定: 数えるのは見えている行(絞り込み・隠しファイル適用後)。FolderListingView.itemCountHeader の doc とテスト itemCountHeaderCountsVisibleRows で固定。AC5: ディレクトリ監視は存在せず(windowDidBecomeKey の doc: 'ディレクトリ監視はしていない')、一覧は窓がキーになった時・表示設定変更時にのみ再取得される。ヘッダーは表示中の行から導出するので、行と同じ範囲で追随する。選択サブフォルダー(.ownListing)は行自体もキー復帰で再列挙されない既存挙動で、ここでは広げない(監視の追加は別タスク)。AC7: en one/other・ja other の plural variations を追加。描画の複数形は実機未確認(テストはプレースホルダ未解決でないことまで)。

AC6 検証: xcodebuild の成果物 befold.app の en/ja の Localizable.stringsdict に folderListing.itemCount の plural が出ることを plutil で確認(en: one/other、ja: other)。カタログの形は FolderListingPluralTests が固定。AC7: FolderListingView の keyEpoch(NSWindow.didBecomeKeyNotification で加算)を自前列挙とメタデータ取得のタスクキーへ含めた。自動テストは無く、実機でのキー復帰確認が未了。

AC7 検証: FolderListingKeyReturnRefreshTests(実物の FolderListingView + NSTableView の行数)で、ファイル追加+キー復帰通知により一覧が 1→2 行へ追随することを確認。keyEpoch 加算を外すと落ちる(ミューテーション確認済み)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
フォルダー一覧のヘッダーに直下の項目数を表示(見えている行を数える。サイドバー経由・自前列挙の両経路が displayedEntries に合流するので同じ規則)。列挙失敗は『読み取れませんでした』を出して 0 件と区別。en one/other・ja other の plural を追加し、xcodebuild 成果物の stringsdict と実アプリの AX ツリー(『1 項目』)で確認。ディレクトリ監視は無いため、キー復帰で取り直す(FolderListingKeyReturnRefreshTests で固定、外すと落ちる)。
<!-- SECTION:FINAL_SUMMARY:END -->
