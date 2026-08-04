---
id: TASK-301
title: フォルダープレビューが .shared(nil) の間に未フィルタ・幻の一覧を表示する
status: To Do
assignee: []
created_date: '2026-08-04 16:35'
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
- [ ] #1 絞り込み ON でプレビューからフォルダーへ移動しても、未フィルタの全件一覧が一瞬でも表示されない
- [ ] #2 共有一覧の到着待ちの間に、開いているファイル 1 行だけのリストが表示されない
- [ ] #3 フォールバック表示が削除済みファイルを含む古いキャッシュ一覧を提示しない
<!-- AC:END -->
