---
id: TASK-477
title: ViewerToolbarController を責務ごとに extension へ分割する
status: Done
assignee: []
created_date: '2026-08-13 14:20'
updated_date: '2026-08-14 10:23'
labels:
  - refactor
dependencies: []
priority: low
type: chore
ordinal: 122000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/befold/App/ViewerToolbarController.swift` は 387 行あり、dagayn の `refactor_tool(mode="suggest")` で Swift 側の split 候補 2 件のうちの 1 件として挙がっている（型 299 行 / split_pressure 4.84。2026-08-13 実測。上位 25 件の残りはすべて同梱の viewer-bundle.js で、本体 Swift の分割候補はこれと StringChunkReader の 2 件のみ）。

現状 1 ファイルに次の 4 つの責務が同居しており、CLAUDE.md「機能を足すと既存ファイルが file_length / type_body_length を超える」で定めた `Type+Feature.swift` 分割の前例（`SidebarNavigator+FolderNavigation` / `MainMenuBuilder+ViewMenu` / `FileListModel+TreeRows`）と同じ形に当てはまる。

1. `ViewerToolbarHosting` プロトコルと `ToolbarItemSpec` / 項目定義（ファイル冒頭〜L160 付近）
2. 状態同期（`// MARK: - State Synchronization`、`refreshToolbarState` と `apply*State(to:)` 群）
3. アクション（`// MARK: - Action Targets`）
4. `NSToolbarDelegate` 準拠（`// MARK: - NSToolbarDelegate`）

既存の MARK 境界がそのまま分割線になる。振る舞いは変えない純粋な整理であり、機能追加は含まない。

注意点: Swift の `private` はファイルスコープのため、分割先の extension から参照する stored property・ヘルパーは internal へ引き上げる必要がある（`applyHistoryState` などが触る `host` 周り）。引き上げたものには「外から呼んでよいのはどれか」を doc コメントで補うこと。

実施順序: TASK-187（FeatureGate 撤去）と競合しない。ViewerToolbarController は FeatureGate 参照ファイル 7 件に含まれず、doc コメントにも「ツールバー構成（ViewerToolbarController.layout）はゲートで変わらない」と明記されている。ただし TASK-187 が同じ App/ 配下の ModeSegments / MainMenuBuilder を触るため、187 の完了後に着手するほうが差分が読みやすい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerToolbarController.swift が MARK 境界に沿って複数ファイルへ分割され、各ファイルが file_length の警告閾値を下回る
- [x] #2 分割にあたり internal へ引き上げたメンバーには、外部から呼んでよい範囲を示す doc コメントが付いている
- [x] #3 新規ファイル追加後に xcodegen generate を実行し、xcodebuild build -scheme befold が通る
- [x] #4 swiftlint のベースライン差分がゼロである（/swiftlint-baseline で main と比較）
- [x] #5 振る舞いの変更がなく、既存の ViewerWindowControllerToolbarTests が無改修で通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
分割結果（実測）:
- ViewerToolbarController.swift 177 行（protocol / ToolbarItemSpec / ToolbarEntry / 識別子・layout・stored property・init）
- +State.swift 102 行 / +Actions.swift 43 行 / +ToolbarDelegate.swift 91 行（いずれも file_length 警告閾値 400 を下回る）
internal へ引き上げたのは ToolbarItemSpec / ToolbarEntry / layout / window / host / apply*State(to:) / segmentLabel / @objc アクション 5 件。すべてに「外から呼んでよい範囲」を doc コメントで明記した。
検証: xcodegen generate 済み。swift build / xcodebuild build -scheme befold 成功。swiftlint はベースライン差分ゼロ（main 65 件 / HEAD 65 件、正規化後 diff なし）。swift test --filter Toolbar は 13 件すべて成功（テストは無改修）。

PR #522 の CI（type-group-size）が閾値超過で落ちた。ViewerToolbarController の型グループ（Foo.swift + Foo+*.swift の合算）が 413 行で閾値 400 超。extension への分割では合算値が減らないため、分割時に増えた import / extension 宣言 / doc コメントのぶんだけ分割前 387 行から増えた形。

例外リスト（scripts/type-group-exceptions.txt）には追加せず、同居していた独立型をファイルごと切り出して返済した。ViewerToolbarHost（protocol）を ViewerToolbarHost.swift へ、ToolbarItemSpec / ToolbarEntry を ToolbarItemSpec.swift へ移動。どちらも元から ViewerToolbarController とは別の型で、1 ファイルに同居していたのが変則だった。

結果: 型グループ 413 → 325 行（本体 89 / +State 102 / +ToolbarDelegate 91 / +Actions 43）。scripts/check-type-group-size.sh --check が exit 0。xcodebuild build -scheme befold は BUILD SUCCEEDED、swiftlint のルール別件数は main と一致のまま。
<!-- SECTION:NOTES:END -->
