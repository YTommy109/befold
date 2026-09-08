---
id: TASK-592
title: オーバーフロー項目の Kind→意味の対応表を SidebarOverflowItem に一本化する
status: Done
assignee:
  - '@claude'
created_date: '2026-09-05 02:48'
updated_date: '2026-09-08 11:16'
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
`SidebarHeaderView.displayChange(for: SidebarOverflowItem.Kind)`（項目 → `SidebarDisplayChange`）と `SidebarHeaderControlsModel.overflowItems(sortOrder:showHiddenFiles:)`（項目 → `isChecked` の判定）が、同じ 1:1 の意味を別ファイルで二重に符号化している。交差した対応（例: `.sortAlphabetical → .setSortOrder(.foldersFirst)`）はコンパイルが通り、`overflowItemsMapToDisplayChanges` が表を手書きで再掲して捕まえるだけで、モデル側の `SidebarHeaderControlsModelTests` とも突き合わない（チェックマークはある順序、選択は別の順序を適用、という不一致を見られない）。

main では同じ switch が `selectOverflowItem` にインラインであり、TASK-586 は持ち上げてテストを付けただけなので悪化はさせていない。`SidebarOverflowItem` に `change: SidebarDisplayChange` を持たせ（Hashable は合成可能、`SortOrder: String`）、`isChecked` をそこから導出し、`SidebarHeaderControls` は `item.change` を発行して `displayChange(for:)` とそのテストを削除する形で、表を 1 つにできる。

/code-review high（2026-09-05）の指摘。TASK-593.1 で `SidebarDisplayRequest` の包みが撤去され、対応表の右辺は `SidebarDisplayChange` そのものになった（1 段の変換が減っている）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 オーバーフロー項目の識別子が SidebarDisplayChange そのものになり、Kind との対応表がコード上に存在しない
- [x] #2 isChecked が change から導出され、SidebarOverflowItem の init に isChecked を渡せない（チェックマークと適用がずれる書き方ができない）
- [x] #3 SidebarHeaderView.displayChange(for:) とそれを再掲する SidebarDisplayChangeRoutingTests のケースが削除され、SidebarHeaderControlsModelTests が map(\.change) で並びと対応を固定している
- [x] #4 「今 ON か」の判定が SidebarDisplaySettings.isOn(_:) の 1 箇所になり、SidebarDisplayMenuState の checks* もそこから導出されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
設計レビュー(/review-design)の結論。案 B（Kind ごと撤去）+ F3（メインメニュー側の「今 ON か」判定と統合）を採る。

1. `SidebarDisplaySettings.isOn(_ change: SidebarDisplayChange) -> Bool` を新設する。4 ケースを網羅する switch にし、`default` を置かない（項目を足したときに「適用はするがチェックが付かない」形をコンパイルで止める）。`.toggleLayoutMode` → `layoutMode == .tree` は既存の `SidebarDisplayMenuState.checksTreeLayout` と同じ定義。
2. F3: `SidebarDisplayMenuState` の `hidesHiddenFiles` / `checksChangedFilesOnly` / `checksTreeLayout` を `isOn(_:)` から導く。「今 ON か」の定義をアプリ内で 1 つにする。
3. `SidebarDisplayChange` に `Hashable` を足す（ForEach の id に使うため。SortOrder が String raw value なので合成できる）。
4. `SidebarOverflowItem`: `Kind` を撤去し `change: SidebarDisplayChange` を持たせる。**明示 init を書いて `isChecked` を引数から外し**、`settings.isOn(change)` から必ず導出する（memberwise init を残すと isChecked を外から任意に渡せてしまい、AC#2 が担保されない）。
5. `SidebarHeaderControlsModel.init` を `settings: SidebarDisplaySettings` を受ける形へ（7 引数 → 4 引数）。4 値を個別引数で持ち回らない方針（`SidebarDisplayOverrides` の doc、TASK-413 と同型）にも合わせる。
6. `SidebarHeaderControls`: `onSelectOverflowItem` の型を `(SidebarDisplayChange) -> Void` にし、ForEach の id を `\.change` にする。
7. `SidebarHeaderView`: `displayChange(for:)` と `selectOverflowItem(_:)` を削除し、`onSelectOverflowItem: perform` を直接渡す（対応表そのものが無くなる）。
8. テスト: `SidebarDisplayChangeRoutingTests.overflowItemsReachDelegate`（表の手書き再掲）を削除。`SidebarHeaderControlsModelTests` を `map(\.change)` の配列比較へ移し、並びと対応を 1 本のアサートで固定する。`isOn(_:)` の 4 ケースをユニットテストで固定する。
9. AC#1 / #3 の文面を案 B に合わせて書き換える。

レビューで拾った担保（項目 9）: AC#2 を守るのは明示 init。doc コメントではなく、isChecked を引数に取れない構造にすることで破れなくする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
設計レビュー(/review-design)を実施し、案 B（Kind ごと撤去）+ F3（メインメニュー側との統合）をユーザー承認のうえ採用した。AC は案 B に合わせて書き換え済み。

実装:
- SidebarDisplaySettings.isOn(_:) を新設（4 ケース網羅、default なし）。SidebarDisplayMenuState の hidesHiddenFiles / checksChangedFilesOnly / checksTreeLayout の 3 つともここから導くようにした。
- SidebarOverflowItem から Kind を撤去し change: SidebarDisplayChange を identity にした。init は (change:titleKey:in:) で、isChecked は settings.isOn(change) から導出する。
- SidebarHeaderControlsModel.init を settings: SidebarDisplaySettings を受ける形へ（7 引数 → 4 引数）。4 値を個別引数で持ち回らない方針（SidebarDisplayOverrides の doc、TASK-413 と同型）に合わせた。
- SidebarHeaderControls の onSelectOverflowItem を (SidebarDisplayChange) -> Void にし、ForEach の id を \.change へ。SidebarDisplayChange に Hashable を足した。
- SidebarHeaderView.displayChange(for:) と selectOverflowItem(_:) を削除し、onSelectOverflowItem: perform を直結した。

AC#1 の裏付け（実測）: rg 'SidebarOverflowItem.Kind|displayChange(for:' の Swift ヒットは 0 件。
AC#2 の裏付け（実測）: SidebarOverflowItem(change:titleKey:isChecked:) を書いた探り用テストは 'incorrect argument label in call (have change:titleKey:isChecked:, expected change:titleKey:in:)' でコンパイルが通らない。
AC#3 の裏付け（実測）: overflowItems の 1 件目を .setSortOrder(.alphabetical) へ意図的に交差させると、overflowItemsMapToDisplayChanges と overflowChecksFollowSortOrder の 2 テストが落ちる（チェックマークも一緒にずれる = 分離して書けない）。戻して緑を再確認済み。
AC#4 の裏付け（コード参照 + 実測）: SidebarDisplayMenuState.init の 3 行はいずれも settings?.isOn(...) 経由。SidebarDisplaySettingsTests が 4 ケース（不可視 / 変更のみ / 表示形式 / 並び順は SortOrder.allCases の全組み合わせ）を固定する。

検証: swift build 成功 / swift test 1917 tests・314 suites すべて成功（変更前 1914・313）/ swiftformat fix モードで 0 files formatted / swiftlint 51 件で main と差分ゼロ / check-doc-symbols.sh・check-doc-citations.sh・markdownlint-cli2（81 files, 0 issues）いずれも指摘なし / 型グループ行数は SidebarDisplaySettings 189・SidebarHeaderControlsModel 163・SidebarHeaderView 133・SidebarHeaderControls 86 で閾値 400 に対し余裕あり / 新規テストファイル追加に伴い xcodegen generate 実行済み。

docs/dev/native-app-design.md に「今 ON か」の判定が isOn(_:) の 1 箇所であることと、⋯ の項目が change を identity に持つことを追記した（現在仕様の層なので追随が必要）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
⋯ オーバーフロー項目の Kind を撤去し、項目の identity を SidebarDisplayChange そのものにした。isChecked は SidebarDisplaySettings.isOn(_:) から導出し、init に渡せない構造にしてチェックマークと適用がずれる書き方を塞いだ。同じ述語を View メニューの SidebarDisplayMenuState も読むようにして「今 ON か」の定義をアプリ内で 1 つにした。SidebarHeaderView.displayChange(for:) と、対応表を再掲していた routing テストは削除し、モデル側の map(\.change) 配列比較へ移した。対応を意図的に交差させると 2 テストが落ちること、isChecked を渡すとコンパイルが通らないことを実測で確認。swift test 1917 tests 全通過、swiftlint は main と差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
