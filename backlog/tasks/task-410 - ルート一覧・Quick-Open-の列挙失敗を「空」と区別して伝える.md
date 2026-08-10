---
id: TASK-410
title: ルート一覧・Quick Open の列挙失敗を「空」と区別して伝える
status: To Do
assignee: []
created_date: '2026-08-10 06:25'
labels: []
dependencies: []
priority: low
ordinal: 119000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-404 で `DirectoryEnumeration.sortedContents` は列挙失敗を nil で表現できるようになり、ツリー展開（子リスト）は `.failed` として空フォルダと区別するようになった。

一方、次の 3 経路は **失敗を明示的に空へ畳んだまま**にしてある（TASK-404 のスコープ外）。畳んだ理由はそれぞれの呼び出し箇所の doc コメントに書いてある。

## 対象と現状

1. **サイドバーのルート一覧** — `DirectoryLister.buildEntries` が `childEntries(...) ?? []`。ルート一覧には失敗を出す先が無い（開閉三角は子フォルダの行にしかない）ため空へ畳んでいる。
2. **プレビューのフォルダー一覧** — `FolderListingView` の `.task` が `listEntriesAsync` を使う。`cachedEntries` は既に「nil = 未到着 / [] = 空」の区別を持っており、そこへ失敗を `[]` として流すと `SidebarEmptyState` が「空のフォルダー」と言い切る。既存の区別を壊す方向に落ちている。
3. **Quick Open のパスモード** — `DirectoryLister.allEntriesSorted` が `?? ([], [])`。候補 0 件が「該当なし」と区別できない。

## 参考

- 判断の記録は TASK-404 の Implementation Notes（`/review-design` の結果）
- `DirectoryEnumeration.sortedContents` の doc（失敗と空の意味の違い）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `FolderListingView` が列挙失敗を「空のフォルダー」として表示しない
- [ ] #2 サイドバーのルート一覧で、列挙に失敗したディレクトリを開いたときに空一覧として確定表示しない
- [ ] #3 Quick Open のパスモードで、列挙失敗と候補 0 件が区別される（区別しないと決める場合は理由を Notes に残す）
- [ ] #4 3 経路それぞれについて、失敗時の表示をユニットテストまたは純粋関数のテストで固定している
<!-- AC:END -->
