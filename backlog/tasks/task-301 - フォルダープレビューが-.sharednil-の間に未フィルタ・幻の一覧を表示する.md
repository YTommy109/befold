---
id: TASK-301
title: フォルダープレビューが .shared(nil) の間に未フィルタ・幻の一覧を表示する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 16:35'
updated_date: '2026-08-04 17:03'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: medium
type: bug
ordinal: 470000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の CONFIRMED 指摘 2 件。いずれも FolderListingView が「.shared(nil)（共有一覧の到着待ち）の間に何を描くか」の扱いに起因する。TASK-295 のフォールバック追加が TASK-293 の不変条件（共有モードでは git ステータスと対になっていない一覧を表示しない）を外している。

1. resolveEntries の「.shared(nil) は自前列挙のキャッシュへフォールバック」（FolderListingView.swift:87）により、絞り込み ON でサブフォルダーをプレビュー→ダブルクリックで移動すると、新ディレクトリの gitStatus が届く前にキャッシュ済みの全件一覧が描画され、その後絞り込み済み一覧に縮む＝TASK-293 で消した「全件フラッシュ」が復活。またキャッシュは再列挙されないため、プレビュー後に削除されたファイルが残り、その行を開くと file-not-found になる。

2. loadedEntries が nil の読み込み中に visibleEntries(from: []) が openFile を追記する（FolderListingView.swift:97）ため、親へ移動→開いているファイルのディレクトリへ戻ると、本来ブランクであるべきロード中状態が「開いているファイル 1 行だけの幻リスト」→全件一覧、とチラつく。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 絞り込み ON でプレビューからフォルダーへ移動しても、未フィルタの全件一覧が一瞬でも表示されない
- [x] #2 共有一覧の到着待ちの間に、開いているファイル 1 行だけのリストが表示されない
- [x] #3 フォールバック表示が削除済みファイルを含む古いキャッシュ一覧を提示しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
着手前に単純化を検討した。TASK-295 の「.shared(nil) の間はビュー側のキャッシュへ退避」は、ビューが「git 状態と対になった一覧を待つべきか」を知らないまま退避先を決めているのが原因。判断材料(showChangedFilesOnly / gitStatus)を持つ FileListModel.listingSource 側へ決定を移せば、ビューの分岐は増えるどころか減る。

1. FileListModel.listingSource: 一覧が未着(hasLoadedEntries でない or entriesDirectory とずれ)のとき、git 絞り込みが ON のときだけ .shared(nil)(= 待つ)を返し、OFF なら .ownListing を返す。OFF なら git 状態と対にする必要がないので待つ理由がなく、TASK-295 の空白も出ない。
2. FolderListingView.resolveEntries のキャッシュ退避を削除する。.ownListing 経路は ListingKey の usesOwnListing が変わることで .task が再走し、**その場で列挙し直す**ため古いキャッシュ(削除済みファイル)を出さない(AC #3)。
3. body: loadedEntries が nil の間は visibleEntries(from:) を通さず空リストにする。appendingOpenFile が「開いているファイル 1 行だけの幻リスト」を作るのを止める(AC #2)。
4. 回帰テストを FolderListingViewFilterTests へ追加・更新し、修正を戻すと落ちることを実測する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手前に単純化を検討した。TASK-295 が置いた「ビュー側のキャッシュへ退避」は、退避の可否を決める材料(showChangedFilesOnly / gitStatus)をビューが持っていないのが問題の根。判断を FileListModel.listingSource へ寄せることで、ビューの分岐は 1 つ減り(resolveEntries の `?? cached` を削除)、状態も増えていない。

1. FileListModel.listingSource: 一覧が未着の間は showChangedFilesOnly が ON のときだけ .shared(nil)(待つ)を返し、OFF なら .ownListing を返す。OFF は対にすべき git 状態が無いので待つ理由がなく、TASK-295 の「移動直後に空へ落ちる」も出ない。
2. FolderListingView.resolveEntries: .shared(nil) のキャッシュ退避を削除。.ownListing 経路は ListingKey の usesOwnListing 変化で .task が再走し**その場で列挙し直す**ため、古いキャッシュ(削除済みファイル)は出ない。
3. FolderListingView.displayedEntries を新設し、未取得(nil)を空配列へ潰さずそのまま返す。body は `displayedEntries ?? []` を List へ渡し、空状態オーバーレイは `if let entries` で判定する。appendingOpenFile が到着待ちに「開いているファイル 1 行だけの幻リスト」を作る経路を断った。

検証: 追加・更新した 3 テストとも、修正を 1 つずつ戻すと実際に失敗することを実測した。
- listingSource の分岐を .shared(nil) 固定へ戻す → 「絞り込み OFF なら、一覧が届く前のプレビューは自前で列挙する」が失敗
- resolveEntries に `?? cached` を戻す → 「一覧の到着待ちでは、自前列挙のキャッシュへ退避しない」が失敗(キャッシュ 2 件が返る)
- displayedEntries を `visibleEntries(from: loadedEntries ?? [])` へ戻す → 「一覧の到着待ちでは、開いているファイル 1 行だけのリストを出さない」が失敗し、notes.xyz 1 行だけの幻リストが実際に再現した

swift test 全体 1092 tests / 161 suites 通過。swiftlint は変更した 3 ファイルについて main とのベースライン差分ゼロ(差分に出る SidebarNavigator / ViewerWindowManager / SidebarNavigatorGitStatusTests は本ブランチの先行コミット由来で本変更とは無関係)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
.shared(nil)(共有一覧の到着待ち)の間に何を描くかを整理し、CONFIRMED 指摘 2 件を解いた。TASK-295 がビュー側に置いたキャッシュ退避を削除し、「待つべきか」の判断を材料を持つ FileListModel.listingSource へ移した(git 絞り込み ON のときだけ待たせ、OFF なら自前列挙させる)。これで絞り込み ON の移動で未フィルタの全件が出ず、待たない経路は列挙し直すので削除済みファイルも残らない。あわせて displayedEntries を新設し、未取得を空配列へ潰して appendingOpenFile に「開いているファイル 1 行だけの幻リスト」を作らせる経路を断った。修正を 1 つずつ戻すと対応するテストが実際に落ちることを実測(3/3)。swift test 1092 tests 通過、swiftlint は変更ファイルでベースライン差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
