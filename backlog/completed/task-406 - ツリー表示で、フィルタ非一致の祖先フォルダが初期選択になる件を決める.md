---
id: TASK-406
title: ツリー表示で、フィルタ非一致の祖先フォルダが初期選択になる件を決める
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 04:00'
updated_date: '2026-08-10 07:23'
labels: []
dependencies: []
priority: low
type: task
ordinal: 663000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`FileListModel.firstSelectableEntryURL` は `visibleEntries` の `.parentNavigation` 以外の先頭を返す。

TASK-361.5 で「絞り込みで残った行の祖先フォルダは、自分が一致しなくても残す」を入れたため、ツリー表示 + 名前フィルタの状態でフォルダへ移動すると、**フィルタに一致していない祖先フォルダが初期選択になりうる**。

## 決めること

- 現状維持（見えている先頭を選ぶ）でよいか
- 一致した行を優先するか（祖先として残っただけの行は飛ばす）

## 現状

TASK-361.5 のレビューで指摘された。祖先保持の実装はブロックしないため、そちらでは扱わなかった。

## 参考

- `Viewer/FileListModel.swift` の `firstSelectableEntryURL`
- `Viewer/SidebarTreeFilter.swift` — 祖先保持の実装
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ツリー表示 + 名前フィルタ時の初期選択の規則が決まり、理由とともに記録されている
- [x] #2 決めた規則がテストで検証されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 規則を決める: 初期選択は「絞り込みに一致した行」を優先し、祖先として足し戻されただけの行は飛ばす。一致行が無い場合のみ従来どおり見えている先頭を採る。
2. FileListModel.firstSelectableEntryURL を、visibleEntries と filteredEntries(祖先足し戻し前)の積で先頭を採る形へ変更する。新しい状態は増やさない。
3. 理由を doc コメントへ記録する。
4. FileListModelTreeFilterTests に (a) 祖先が先頭でも一致行が選ばれる (b) 一致行が無ければ従来どおり のテストを足す。
5. swift test / swiftformat / swiftlint 差分ゼロを確認してコミットする。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めた規則

**初期選択は「絞り込みに一致した行」を優先し、祖先として足し戻されただけの行は飛ばす。** 一致行が 1 つも無い場合のみ、従来どおり見えている先頭(`..` を除く)を採る。

理由: 絞り込みは「見つけるための機能」であり、ツリー表示で祖先フォルダが自分は一致しないまま残るのは孤児行を出さないための構造上の措置にすぎない。見えている先頭をそのまま採ると、絞り込み中にフォルダを降りるたび、探していた行まで矢印キーで降りることになる。無選択へ落とさないフォールバックは残す(移動先で 1 行選ばれているほうが安全)。

## 実装（単純化検討の結果）

修正前に単純化の余地を検討した。新しい状態・述語・経路は増やさず、既にある `filteredEntries`(祖先足し戻し**前**の絞り込み結果)との積を取るだけで規則が表現できるため、その形を採用した。祖先かどうかを表す新しいフラグや `SidebarTreeFilter` の戻り値の拡張は不要。

- `FileListModel.firstSelectableEntryURL`: `visibleEntries` の `.parentNavigation` 以外のうち、`filteredEntries` に含まれる先頭を採る(無ければ先頭)。

## 検証

- `swift test`: 1358 tests / 197 suites 全通過
- swiftformat: 差分なし / swiftlint: 変更 2 ファイルとも警告 0 件（`FileListModel.swift` は 400 行ちょうどで file_length 警告に触れないことを実測）
- 追加テスト（`FileListModelTreeFilterTests`）
  - 「ツリー表示 + 名前フィルタでは、祖先が先頭でも一致した行が初期選択になる」
  - 「絞り込みが無ければ、初期選択は `..` を除く見えている先頭のまま」（一致優先が「常に祖先を飛ばす」形へ退化していないことの担保）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツリー表示 + 名前フィルタでフォルダを降りたときの初期選択を「絞り込みに一致した行を優先し、祖先として残っただけの行は飛ばす」規則に決め、FileListModel.firstSelectableEntryURL を visibleEntries と filteredEntries の積で採る形へ変更した。新しい状態・経路は増やしていない。規則と理由は同 property の doc コメントに記録し、一致優先とフィルタ無し時の従来動作を FileListModelTreeFilterTests の 2 件で担保。swift test 1358 件全通過、swiftlint 警告 0 件で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
