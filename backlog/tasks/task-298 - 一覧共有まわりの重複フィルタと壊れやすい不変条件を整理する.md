---
id: TASK-298
title: 一覧共有まわりの重複フィルタと壊れやすい不変条件を整理する
status: To Do
assignee: []
created_date: '2026-08-04 14:47'
labels:
  - git-filter
  - review-finding
  - refactor
dependencies: []
priority: low
ordinal: 496000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) のクリーンアップ指摘 3 件。

1. (CONFIRMED) .shared の場合、FolderListingView.visibleEntries が、サイドバーが既に同じ FileListFilter で絞り込んだ entries に対して同じ apply を再実行しており、body 評価のたびに O(n) のグロブ + git ステータス判定が二重に走る（FolderListingView.swift:67）。空状態オーバーレイに必要な「絞り込み前後の差」はフラグや件数で渡せる。
2. (PLAUSIBLE) entriesDirectory を entries.didSet の中で currentDirectory から刻んでおり、「currentDirectory を書き換える 4 箇所すべてが listingGeneration を bump する」という別オブジェクト側の不変条件に依存している。performListing は列挙した directory を知っているのに捨てている。setEntries(_:for:) 相当にすれば不変条件がローカルに閉じる（FileListModel.swift:22）。
3. (CONFIRMED) ウォッチャーファクトリのクロージャ型 `(URL, @escaping @MainActor @Sendable () -> Void) -> FileWatching` が 2 ファイル 4 箇所に直書きされている。typealias にまとめる（GitIndexWatch.swift:17, SidebarNavigator.swift:58 ほか）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 .shared のフォルダープレビューで同じフィルタが二重適用されない
- [ ] #2 entries に紐づくディレクトリは、列挙した側が明示的に渡す形になっている
- [ ] #3 ウォッチャーファクトリの型が 1 箇所の typealias で定義されている
- [ ] #4 既存テストが通り、swiftlint の main 比ベースライン差分がゼロである
<!-- AC:END -->
