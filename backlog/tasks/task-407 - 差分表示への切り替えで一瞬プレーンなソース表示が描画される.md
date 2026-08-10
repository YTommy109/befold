---
id: TASK-407
title: 差分表示への切り替えで一瞬プレーンなソース表示が描画される
status: To Do
assignee: []
created_date: '2026-08-10 05:59'
updated_date: '2026-08-10 14:04'
labels:
  - bug
dependencies: []
priority: medium
type: bug
ordinal: 106000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
表示モードを差分表示 (.diff) に切り替えると、いったん差分なしのソースコード表示が描画されてから差分付きの表示に変わる。

原因（実測・コード参照）:
- `ViewerWindowController.setDisplayMode` (App/ViewerWindowController.swift:736) が `applyDisplayMode` で同期に `store.displayMode = .diff` を立てる (:787)。この時点で `store.diffText` は nil なので `ViewerContentView` (Viewer/ViewerContentView.swift:29) が渡す `diffState` は `.none`。
- `isSourceMode` が false→true に変わるため `ViewerRenderer` が「差分なしのソース表示」で全文描画する (BefoldRenderKit/ViewerRenderer+ContentUpdate.swift:212-226)。これが一瞬見えるプレーンなソース。
- その後 `refreshDiff()` (:761) が `GitDiffLoader.diff` を非同期に呼び、`store.diffText` 着地で 2 度目の全文再描画が走る (App/ViewerWindowController+Diff.swift:35-43)。

構造的な理由:
- `GitDiffLoader` は結果をキャッシュしない方針（App/GitDiffLoader.swift:3-8 の doc）で、切替時に即使える同期値が存在しない。
- 取得は `Task.detached` でサブプロセス `git` を起こすため (GitDiffLoader.swift:97)、`@MainActor` から同期に待てない。
- したがって `applyDisplayMode` と `refreshDiff` の呼び出し順を入れ替えても解消しない。

再現条件: `.rendered → .diff` の遷移でのみ発生する。`.source → .diff` は `isSourceMode` も `diffState` も変わらず 1 段目の再描画が `incoming != rendered` で弾かれる (ContentUpdate.swift:214) ため発生しない。

方針の候補（着手時に `/review-design` で確定する）:
(a) `ViewerRenderer.DiffState` (ViewerRenderer+ContentUpdate.swift:54-63) に未確定を表す状態を足し、diff 未着の間は 1 段目の描画を見送って前の表示を残す
(b) ViewerWebView 側で `store.diffText == nil && showsDiff` の間だけレンダリングを遅らせる（判定が View 層に散る）
(c) `GitDiffLoader` に短命キャッシュを持たせる（非キャッシュ方針に反するため非推奨）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `.rendered` から差分表示へ切り替えたとき、差分なしのプレーンなソース表示が中間状態として描画されない
- [ ] #2 `.source` から差分表示への切り替えなど既存の遷移で余計な再描画が増えていない
- [ ] #3 差分の取得に失敗した場合・差分が空の場合の表示が退行していない
- [ ] #4 中間状態を描画しないことがユニットテストで担保されている（描画ミラーの遷移列を検証する形）
- [ ] #5 着手前に `/review-design` を 1 回実行し、結果を Implementation Plan に反映している
<!-- AC:END -->
