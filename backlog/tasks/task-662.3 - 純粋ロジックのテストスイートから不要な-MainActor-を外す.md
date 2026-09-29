---
id: TASK-662.3
title: 純粋ロジックのテストスイートから不要な @MainActor を外す
status: To Do
assignee: []
created_date: '2026-09-29 04:29'
labels: []
dependencies: []
parent_task_id: TASK-662
priority: medium
ordinal: 859000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
並列実行の律速はメインキュー（TASK-662 の実測）。対象の型が非隔離なのにスイートごと @MainActor になっているテストは、メインキューに並ぶ必要がない。1 件ごとの効果は小さいが変更はほぼ 1 行で、TASK-607 の飢餓も減らす方向。

## 該当（対象型が非隔離であることをレビューで確認済み）
- `FileListSnapshotFileNeighbourTests`（7 件）: `FileListSnapshot` は非隔離 struct
- `FocusTraversalTests` の前半 4 件: 非隔離 enum `SidebarKeyAction.action(...)` だけを測る。NSMenu を使う後半とスイートを分ける
- `ViewerDisplayModeSupportTests`（5 件）: `ViewerDisplayMode` は Sendable enum
- `ViewerWindowKindTests`（6 件）: enum の述語と定数だけ（同ファイルの `SlideWindowSidebarGuardTests` は残す）
- `ViewerBridgeContractTests`（14 件）: @MainActor の理由は `ZoomStore` の static 定数参照だけ。`ZoomStore` の `static let` を `nonisolated` にすれば外せる
- `SidebarDisplayMenuStateTests`（9 件）: `SidebarDisplayMenuState` / `SidebarDisplaySettings` は非隔離 struct
- `SidebarTreeLayoutTests`: 先頭テストは `SidebarRowBuilder.rows` だけ。@MainActor をテスト単位へ下ろす

## 同じ理由で直すもの（MainActor 上の cfprefsd XPC）
`CodeFontPreferenceTests` / `CsvNumberFormatPreferenceTests`（UUID 名の suite で plist が実行ごとに堆積）/ `DiffDisplayPreferenceTests` がディスクの `UserDefaults(suiteName:)` を使っている。共有ヘルパー `makeIsolatedDefaults(prefix:)`（メモリ上）へ置き換える
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 上記スイートの @MainActor が外れる（またはテスト単位へ下りる）か、外せない理由が Notes にある
- [ ] #2 3 ファイルのディスク UserDefaults が makeIsolatedDefaults に置き換わっている
- [ ] #3 swiftlint のベースライン差分がゼロ（/swiftlint-baseline）
<!-- AC:END -->
