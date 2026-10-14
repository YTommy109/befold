---
id: TASK-707
title: プレビュー内のフォルダー一覧に変更日・サイズ・種類を Finder のように表示する
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
ordinal: 896000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
フォルダーを選んだときにコンテンツエリアへ出る一覧(FolderListingView)の各行はアイコンと名前だけで、更新の新しさや大きさ、種類が分からない。Finder のリスト表示のように、各ファイル・フォルダー行に変更日・サイズ・種類を出したい(利用者要望)。**対象はコンテンツエリアの一覧のみで、サイドバーは現状のまま変えない。** 注意: 行表示 FileListEntryRow はサイドバーと共有している(native-app-design.md)ので、共有部品に足すとサイドバーも変わる。一覧側だけに足す形にすること。着手前に決める点: (1) 列(Table 風)にするか行内テキストにするか、幅が狭いときの規則 (2) メタデータの取得を DirectoryLister の列挙(buildEntries)の resourceValues に載せるか、遅延取得するか。巨大フォルダーで MainActor を塞がないこと (3) フォルダーのサイズは Finder 同様に空欄とするか (4) 種類の文言を FileType と Finder の localizedTypeDescription のどちらに揃えるか。実装前に /review-design を回す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 コンテンツエリアの一覧の各ファイル行に変更日・サイズ・種類が表示され、フォルダー行は変更日と種類が表示される(サイズの扱いは決定どおり)
- [x] #2 サイドバーの表示・挙動は変わらない(FileListEntryRow の共有を壊さないことを、サイドバー側のテストまたは目視で確認する)
- [x] #3 一覧の幅が狭いときの表示規則(省略・折り畳み)が決まっており、VoiceOver が各行の変更日・サイズ・種類を読み上げる
- [x] #4 メタデータの取得は MainActor の外で行われ、1 万件規模のフォルダーを開いて一覧が出るまでの時間が導入前から有意に悪化しない(実測値を Notes に残す)
- [x] #5 ファイルの内容更新を監視が検知したとき、その行の変更日・サイズが更新される
- [x] #6 日付・サイズの書式は利用者のロケールに従い、表示文字列は Localizable.xcstrings に en/ja で追加される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. メタデータは FileListEntry/DirectoryLister に載せず、FolderListingView 内の @State 辞書へ MainActor 外(nonisolated async)で取得する(サイドバー・BefoldKit の列挙に stat を足さない)。2. 行は FileListEntryRow を包む FolderListingRow(共有部品は無変更)。3. フォルダーのサイズは空欄、種類は localizedTypeDescription(Finder と同じ・OS が翻訳)。拡張子ごとにキャッシュ。4. 幅が狭いときは名前を中間省略し、列は折り返さず固定幅。5. 取得キー=行の url 列+開いているファイルの contentRevision。6. 1 万件の実測は一時テストで取得時間を測り Notes に残す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
決定: (1) 行内の固定幅列(変更日130/サイズ64/種類110)、狭いときは名前が中間省略され列は折り返さない。(2) FileListEntry/DirectoryLister/BefoldKit には載せず、FolderListingView の @State へ nonisolated async(FolderListingMetadata.load)で取得。FileListEntryRow は無変更でサイドバー影響なし(AC2)。(3) フォルダーのサイズは空欄。(4) 種類は localizedTypeDescription(Finder と同じ・OS 翻訳)、拡張子ごとにキャッシュ。AC4 実測(一時テスト、1 万ファイル、debug ビルド): 一覧列挙 0.43s、メタデータ取得 0.87s(MainActor 外)。一覧は取得を待たず先に出るので表示までの時間は導入前と同じ。AC6: 日付・サイズは Date/ByteCount の formatter(ロケール追従)、種類は OS 提供の文字列で、追加すべき文言は無い。落とし穴: URL は resourceValues を自分でキャッシュするため、同じ URL で再取得すると古い値が返る → removeAllCachedResourceValues を呼ぶ(FolderListingMetadataTests.reloadReflectsContentChange が固定)。AC5: ディレクトリ監視は無く、取り直しの契機は『行の url 列の変化』と『開いているファイルの contentRevision』のみ。他ファイルの内容更新(窓がキーに戻っただけ)では日付が更新されない。要判断: フォルダー監視を足すか AC を縮小するか。未実施: AC1/3 は実機での目視・VoiceOver 確認が未了(GUI は自動テスト対象外)。

AC5 の対応: FolderListingView の keyEpoch(キー復帰で加算)を自前列挙とメタデータ取得のタスクキーに含め、サイドバーの再取得と同じ契機で取り直す。取得側の更新はテストで固定済み、キー復帰からの配線は自動テスト無し・実機確認未了。AC3 の VoiceOver: 行を accessibilityElement(.combine) でまとめたが、ヘッドレスでは SwiftUI の AX ツリーが空で読み上げ文字列を検証できなかった。実機確認はリリース前の手動チェックへ。

実機相当の確認(2026-10-14): ImageRenderer で FolderListingRow を画像化して目視し、変更日が『22:…』、種類が『Markdown docu…』で切れていたため、日付を .numeric にして列幅を 120/64/150 へ直した(修正後は 3 列とも切れず、長い名前だけが中間省略される=狭い幅の規則を確認)。AC5: FolderListingKeyReturnRefreshTests が実物の FolderListingView を窓に載せ、ファイル追加+キー復帰通知で NSTableView の行が 1→2 になることを確認。keyEpoch 加算を外すと落ちることも確認済み(メタデータ取得も同じ keyEpoch をキーにしている)。AC3 の VoiceOver 読み上げ文字列は、ヘッドレスでは AX ツリーが空で検証不能(2 回試行)。

AC3 検証(2026-10-14): ビルドした Debug アプリを起動し、System Events 経由で実際のアクセシビリティツリーを取得。フォルダー一覧の行が『b.json、2026年10月14日 22:43、3バイト、JSON Document』の 1 要素(名前・変更日・サイズ・種類)として公開されることを確認。VoiceOver が読む AX ツリーそのもの。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
フォルダー一覧の各行に変更日・サイズ・種類を表示。メタデータは FileListEntry/DirectoryLister に載せず FolderListingView が MainActor の外で取得(サイドバー無変更)。1 万ファイルで列挙 0.43s・取得 0.87s(一覧は取得を待たず先に出る)。URL の resourceValues キャッシュで再取得が古い値を返す問題を修正。列幅は ImageRenderer の目視で日付・種類の切れを直した。キー復帰での取り直しは FolderListingKeyReturnRefreshTests(外すと落ちる)、VoiceOver は実アプリの AX ツリーで確認。
<!-- SECTION:FINAL_SUMMARY:END -->
