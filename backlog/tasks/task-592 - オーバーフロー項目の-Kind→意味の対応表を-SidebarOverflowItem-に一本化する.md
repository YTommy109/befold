---
id: TASK-592
title: オーバーフロー項目の Kind→意味の対応表を SidebarOverflowItem に一本化する
status: To Do
assignee: []
created_date: '2026-09-05 02:48'
updated_date: '2026-09-05 02:48'
labels:
  - sidebar
dependencies:
  - TASK-590
priority: low
type: enhancement
ordinal: 857000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`SidebarHeaderView.displayRequest(for: SidebarOverflowItem.Kind)`（項目 → SidebarDisplayRequest）と `SidebarHeaderControlsModel.overflowItems(sortOrder:showHiddenFiles:)`（項目 → `isChecked` の判定）が、同じ 1:1 の意味を別ファイルで二重に符号化している。交差した対応（例: `.sortAlphabetical → .setSortOrder(.foldersFirst)`）はコンパイルが通り、`overflowItemsMapToDisplayRequests` が表を手書きで再掲して捕まえるだけで、モデル側の `SidebarHeaderControlsModelTests` とも突き合わない（チェックマークはある順序、選択は別の順序を適用、という不一致を見られない）。

main では同じ switch が `selectOverflowItem` にインラインであり、TASK-586 は持ち上げてテストを付けただけなので悪化はさせていない。`SidebarOverflowItem` に `change: SidebarDisplayChange` を持たせ（Hashable は合成可能、`SortOrder: String`）、`isChecked` をそこから導出し、`SidebarHeaderControls` は `item.change` を発行して `displayRequest(for:)` とそのテストを削除する形で、表を 1 つにできる。

/code-review high（2026-09-05）の指摘。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 オーバーフロー項目の Kind と SidebarDisplayChange の対応がコード上 1 箇所にしか無い
- [ ] #2 `isChecked` がその対応から導出され、チェックマークと選択時の適用がずれる書き方ができない
- [ ] #3 `SidebarHeaderView.displayRequest(for:)` とそれを再掲するテストが削除され、モデル側テストが `change` を検証している
<!-- AC:END -->
