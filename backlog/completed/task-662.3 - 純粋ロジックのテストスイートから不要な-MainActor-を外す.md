---
id: TASK-662.3
title: 純粋ロジックのテストスイートから不要な @MainActor を外す
status: Done
assignee: []
created_date: '2026-09-29 04:29'
updated_date: '2026-09-29 06:44'
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
- [x] #1 上記スイートの @MainActor が外れる（またはテスト単位へ下りる）か、外せない理由が Notes にある
- [x] #2 3 ファイルのディスク UserDefaults が makeIsolatedDefaults に置き換わっている
- [x] #3 swiftlint のベースライン差分がゼロ（/swiftlint-baseline）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
Package.swift に defaultIsolation が無いことを確認し、対象スイートの @MainActor を外してコンパイラに隔離を判定させる。FocusTraversalTests はキー割り当て側を別スイートへ分割、SidebarTreeLayoutTests は UserDefaults を触る 2 件だけテスト単位へ下ろす。ZoomStore の static 定数を nonisolated にする。Preference 3 スイートは makeIsolatedDefaults へ置き換える。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
外せなかったスイートは無い。FocusTraversalTests はキー割り当て 4 件を FocusTraversalKeyTests（非隔離）へ分け、NSMenu を使う残り 4 件は @MainActor の FocusTraversalTests に残した。SidebarTreeLayoutTests は SidebarDisplayDefaults を触る 2 件だけ @MainActor。Preference 3 スイートは対象型が @MainActor 前提のため suite の @MainActor は残し、UserDefaults だけ makeIsolatedDefaults に置き換えた。
検証: swift test（並列）2017 件 44.3 秒で全件成功、対象 13 スイート 69 件成功。swiftformat --lint 全ターゲット 0 件。/swiftlint-baseline は main 46 件 / HEAD 46 件で真の新規・解消とも 0。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
純粋ロジックのテスト 7 スイートを MainActor から外し（FocusTraversalTests は分割、SidebarTreeLayoutTests はテスト単位へ下ろす）、ZoomStore の static 定数を nonisolated にした。Preference 系 3 スイートのディスク UserDefaults を makeIsolatedDefaults に置き換えた。swift test 全 2017 件成功・swiftlint ベースライン差分 0 で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
