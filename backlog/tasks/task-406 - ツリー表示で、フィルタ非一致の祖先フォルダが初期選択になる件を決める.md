---
id: TASK-406
title: ツリー表示で、フィルタ非一致の祖先フォルダが初期選択になる件を決める
status: To Do
assignee: []
created_date: '2026-08-10 04:00'
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
- [ ] #1 ツリー表示 + 名前フィルタ時の初期選択の規則が決まり、理由とともに記録されている
- [ ] #2 決めた規則がテストで検証されている
<!-- AC:END -->
