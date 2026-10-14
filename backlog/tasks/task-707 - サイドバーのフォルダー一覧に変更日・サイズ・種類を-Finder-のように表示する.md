---
id: TASK-707
title: プレビュー内のフォルダー一覧に変更日・サイズ・種類を Finder のように表示する
status: To Do
assignee: []
created_date: '2026-10-14 04:31'
updated_date: '2026-10-14 04:33'
labels:
  - sidebar
dependencies: []
priority: low
ordinal: 896000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
フォルダーを選んだときにコンテンツエリアへ出る一覧(FolderListingView)の各行はアイコンと名前だけで、更新の新しさや大きさ、種類が分からない。Finder のリスト表示のように、各ファイル・フォルダー行に変更日・サイズ・種類を出したい(利用者要望)。**対象はコンテンツエリアの一覧のみで、サイドバーは現状のまま変えない。** 注意: 行表示 FileListEntryRow はサイドバーと共有している(native-app-design.md)ので、共有部品に足すとサイドバーも変わる。一覧側だけに足す形にすること。着手前に決める点: (1) 列(Table 風)にするか行内テキストにするか、幅が狭いときの規則 (2) メタデータの取得を DirectoryLister の列挙(buildEntries)の resourceValues に載せるか、遅延取得するか。巨大フォルダーで MainActor を塞がないこと (3) フォルダーのサイズは Finder 同様に空欄とするか (4) 種類の文言を FileType と Finder の localizedTypeDescription のどちらに揃えるか。実装前に /review-design を回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 コンテンツエリアの一覧の各ファイル行に変更日・サイズ・種類が表示され、フォルダー行は変更日と種類が表示される(サイズの扱いは決定どおり)
- [ ] #2 サイドバーの表示・挙動は変わらない(FileListEntryRow の共有を壊さないことを、サイドバー側のテストまたは目視で確認する)
- [ ] #3 一覧の幅が狭いときの表示規則(省略・折り畳み)が決まっており、VoiceOver が各行の変更日・サイズ・種類を読み上げる
- [ ] #4 メタデータの取得は MainActor の外で行われ、1 万件規模のフォルダーを開いて一覧が出るまでの時間が導入前から有意に悪化しない(実測値を Notes に残す)
- [ ] #5 ファイルの内容更新を監視が検知したとき、その行の変更日・サイズが更新される
- [ ] #6 日付・サイズの書式は利用者のロケールに従い、表示文字列は Localizable.xcstrings に en/ja で追加される
<!-- AC:END -->
