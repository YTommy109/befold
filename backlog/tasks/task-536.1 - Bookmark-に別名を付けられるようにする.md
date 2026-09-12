---
id: TASK-536.1
title: Bookmark に別名を付けられるようにする
status: In Progress
assignee:
  - '@claude'
created_date: '2026-08-21 07:27'
updated_date: '2026-09-12 13:20'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 777000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在ブックマークはパス文字列のみを保持し、表示名は常に `lastPathComponent` から算出される（`BookmarksMenuController.swift:29-44`）。任意の別名（表示名）を設定・保存できるようにする。

データモデル（`BookmarkStore` もしくは `PathListDefaults` 相当）に、ファイルパスと関連付けた表示名フィールドを追加する。既存の `noteRenamed(from:to:)`（`BookmarkStore.swift:56-58`、ファイルのリネーム・移動時にパスを追随させる仕組み）との整合を保つこと（パスは追随するが、ユーザーが設定した別名は保持される必要がある）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブックマークごとに別名を設定できる（管理パネル Bookmarks > Edit Bookmarks… の右クリック「別名を変更…」）
- [ ] #2 別名未設定のブックマークは従来どおりファイル名で表示される
- [ ] #3 別名を設定したブックマークは Bookmarks メニューの一覧と管理パネルに別名で表示される（パス列はそのまま）
- [ ] #4 ファイルのリネーム・移動時、パスが更新されても設定済みの別名（と所属フォルダー）は保持される
- [ ] #5 別名の保存・読み込み・リネーム時の保持をユニットテストで担保する
- [ ] #6 永続化を新キー Bookmarks（JSON の BookmarkLibrary）へ移し、旧キー BookmarkedPaths からの一度きり移行を (a) 旧値あり (b) 旧値なし (c) 移行済み の 3 ケースのユニットテストで担保する。旧キーは移行の有無にかかわらず削除される
- [ ] #7 既存の読み手（Bookmarks メニュー / MissingBookmarksPruner / Quick Open / ツールバー）と書き手（⌘D / FileNotFoundUI / CLI --bookmark）は API 変更なしで動き、既存テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に BookmarkLibrary（folders / entries、名前列で階層）を値型で新設し、追加・削除・別名・rename 追随の純粋操作をここへ置く
2. BookmarkStore を「読む→1 操作→書く」の薄層にし、新キー Bookmarks（JSON Data）へ移す。init で旧キー BookmarkedPaths を一度だけ移行し defer で削除する
3. 既存 API（isBookmarked/add/toggle/remove/removeAll/bookmarkedURLs/noteRenamed）の意味を保つ。library() と setAlias(_:for:) を足す
4. NSMenu.addFileItems に表示名を渡せる形を足し、BookmarksMenuController が alias ?? lastPathComponent で並べる
5. HostedPanel.bookmarks と BookmarkManagerView / BookmarkManagerModel を新設（一覧・別名変更 alert・ダブルクリックで開く）。Bookmarks メニュー固定部に「Edit Bookmarks…」（キー等価なし）を足し、組み立て時と再生成時の両方で置く
6. テスト: BookmarkLibraryTests / BookmarkStoreMigrationTests（3 ケース）/ BookmarkStoreTests に alias 保持 / BookmarksMenuControllerTests に alias 表示と固定部 2 項目 / MainMenuBuilderTests
7. xcodegen generate、swiftformat、swift test、xcodebuild、swiftlint ベースライン、l10n-check。MainMenuBuilder の例外上限を実測値へ更新
<!-- SECTION:PLAN:END -->
