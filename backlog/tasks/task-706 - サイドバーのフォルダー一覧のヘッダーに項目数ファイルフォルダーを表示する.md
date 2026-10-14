---
id: TASK-706
title: プレビュー内のフォルダー一覧のヘッダーに項目数(ファイル+フォルダー)を表示する
status: In Progress
assignee: []
created_date: '2026-10-14 04:31'
updated_date: '2026-10-14 13:19'
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
- [ ] #5 ファイル追加・削除を監視が検知したとき、件数が追随する
- [x] #6 列挙に失敗したフォルダーでは 0 件と区別できる表示になる
- [ ] #7 表示文字列は Localizable.xcstrings に en/ja で追加され、1 件・複数件の複数形が崩れない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 件数は displayedEntries(見えている行)を数える。両供給元が合流するので同じ規則(AC4)。2. 列挙失敗は既存の folder.enumerationFailed を出す。3. 複数形は xcstrings の plural variations。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決定: 数えるのは見えている行(絞り込み・隠しファイル適用後)。FolderListingView.itemCountHeader の doc とテスト itemCountHeaderCountsVisibleRows で固定。AC5: ディレクトリ監視は存在せず(windowDidBecomeKey の doc: 'ディレクトリ監視はしていない')、一覧は窓がキーになった時・表示設定変更時にのみ再取得される。ヘッダーは表示中の行から導出するので、行と同じ範囲で追随する。選択サブフォルダー(.ownListing)は行自体もキー復帰で再列挙されない既存挙動で、ここでは広げない(監視の追加は別タスク)。AC7: en one/other・ja other の plural variations を追加。描画の複数形は実機未確認(テストはプレースホルダ未解決でないことまで)。
<!-- SECTION:NOTES:END -->
