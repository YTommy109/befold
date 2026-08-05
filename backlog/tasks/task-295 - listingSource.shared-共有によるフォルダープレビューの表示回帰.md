---
id: TASK-295
title: listingSource(.shared) 共有によるフォルダープレビューの表示回帰
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 14:46'
updated_date: '2026-08-04 15:32'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: high
type: bug
ordinal: 493000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の検証済み指摘 3 件。いずれも FileListModel.listingSource / FolderListingView の .shared 共有の設計に起因する。

1. (CONFIRMED) プレビュー中のサブフォルダーへ移動すると一瞬空になる。navigateToFolder が currentDirectory を先に更新するため entriesDirectory とずれ、listingSource が .shared(nil) を返す。自前列挙済みの cachedEntries があるのに描画が空リストへ落ちる（FileListModel.swift:217）。
2. (PLAUSIBLE) source が .task(id: listingKey) と .id(directory) のどちらにも入っていないため、directory 据え置きで .shared → .ownListing に切り替わると再列挙が走らず、プレビューが恒久的に空のままになりうる（FolderListingView.swift:90）。
3. (PLAUSIBLE) sidebar の entries には ensureCurrentFile が DirectoryLister の対象外ファイルを追記するため、.shared 経由のカレントディレクトリプレビューにだけその行が現れる。同じフォルダーでも親から選択してプレビューした場合（自前列挙）と内容が食い違う（FileListModel.swift:220）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 プレビュー中のサブフォルダーへ移動しても一覧が空になる瞬間がない
- [x] #2 source が .shared と .ownListing の間で切り替わったとき、ディレクトリが変わらなくても正しい一覧が表示される
- [x] #3 同じフォルダーの内容が、カレントディレクトリ経由と親からの選択経由で一致する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FolderListingView: .shared(nil) のとき自前列挙(同一ディレクトリ)へ退避させ、移動直後の空白を消す
2. ListingKey に usesOwnListing を足し、ディレクトリ据え置きの供給元切り替えで再列挙させる
3. ensureCurrentFile の規則を DirectoryLister.appendingOpenFile へ抽出し、サイドバーとプレビューの両方が同じ実装を通るようにする
4. 上記 3 点の回帰テストを FolderListingViewFilterTests へ追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に単純化を検討した。.shared(nil)(=「まだ待て」)を .ownListing へ潰す案は、TASK-293 の回帰(一覧だけが git 状態より先に着地して絞り込み前の全件が一瞬見える)を戻すため採らない。代わりにビュー側で「同じディレクトリを自前列挙した結果」を退避先にし、状態は増やさずに 3 件とも解いた。

1. FolderListingView.resolveEntries: .shared(nil) のとき cachedEntries へ退避。cachedEntries は .id(directory) でビューごと作り直されるため必ず同一ディレクトリの列挙結果で、別フォルダーの中身が見えることはない。
2. ListingKey に usesOwnListing を追加。ディレクトリ据え置きの .shared → .ownListing 切り替えで .task が再走する。
3. ensureCurrentFile の規則を DirectoryLister.appendingOpenFile へ抽出し、サイドバー(SidebarNavigator)とプレビュー(FolderListingView.visibleEntries)の両方が同じ実装を通すようにした。ViewerContentView が store.filePath を渡す。

検証: 追加した 6 テストのうち 3 件(退避・キー切り替え・開いているファイルの追記)は、修正を 1 つずつ戻すと実際に失敗することを実測済み(3 issues)。修正を戻すと通らない形になっている。swift test 全体 1008 tests / 141 suites 通過。swiftlint はベースライン差分ゼロ(SidebarNavigator:368 の opening_brace は行番号がずれただけの既存分)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
listingSource(.shared) 共有に起因する 3 件を、状態を増やさず解いた。プレビューは .shared(nil) の間だけ自前列挙した同一ディレクトリの一覧へ退避し(移動直後の空白を解消)、ListingKey に usesOwnListing を足して供給元切り替えで再列挙させ、開いているファイルを一覧へ足す規則を DirectoryLister.appendingOpenFile へ抽出してサイドバーとプレビューで共有した。回帰テスト 6 件を追加し、うち 3 件は修正を戻すと落ちることを実測。swift test 1008 tests 通過、swiftlint ベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
