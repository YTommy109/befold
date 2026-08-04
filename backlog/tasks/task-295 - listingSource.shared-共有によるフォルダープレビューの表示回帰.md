---
id: TASK-295
title: listingSource(.shared) 共有によるフォルダープレビューの表示回帰
status: To Do
assignee: []
created_date: '2026-08-04 14:46'
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
- [ ] #1 プレビュー中のサブフォルダーへ移動しても一覧が空になる瞬間がない
- [ ] #2 source が .shared と .ownListing の間で切り替わったとき、ディレクトリが変わらなくても正しい一覧が表示される
- [ ] #3 同じフォルダーの内容が、カレントディレクトリ経由と親からの選択経由で一致する
<!-- AC:END -->
