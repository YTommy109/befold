---
id: TASK-514
title: appliedPageZoom の書き込み入口を 1 つに閉じる
status: To Do
assignee: []
created_date: '2026-08-18 02:54'
labels: []
milestone: m-6
dependencies: []
priority: medium
type: chore
ordinal: 754000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

`ViewerRenderer.appliedPageZoom`（viewer.js へ適用済みの倍率の記録）は、キャッシュ無効化の作法を要求する値でありながら、書き込み入口が型の外に開いている。

実測（TASK-513 の設計レビュー時、ブランチ falcon-ocotillo）:

- `BefoldRenderKit/DirectHTMLModeController.swift:72` と `:118` が `renderer.appliedPageZoom = nil` と他型の stored property を直接書いている
- `BefoldRenderKit/DirectHTMLModeController.swift:57` が `renderer.initialPageZoom` を読む
- `befoldTests/ViewerRendererZoomIntegrationTests.swift:66` もテストから直接 nil を代入している

同じ `ViewerRenderer` の中で、描画済みミラー `rendered` は `private(set)` + `recordRendered` で確定の入口を 1 つに絞ってある（TASK-320 / TASK-334 で 2 度確定漏れが起きたことへの構造対策）。`appliedPageZoom` だけがこの扱いから漏れている。

## 方針

`initialPageZoom`（望む倍率）・`appliedPageZoom`（適用済みの記録）・`applyInitialPageZoomIfReady` を `PageZoomProjector`（仮）へ切り出し、無効化は `invalidateApplied()` 相当のメソッド経由だけにする。

**これは行数削減のタスクではない**（実測で減るのは約 25 行、公開 API `initialPageZoom` の転送プロパティを残せば実質ゼロ）。TASK-513 で行数の動機は既に解消済みなので、合格条件は行数ではなく書き込み入口の閉じ込めに置く。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 appliedPageZoom（相当の値）への書き込みが新しい型の中に閉じ、DirectHTMLModeController は無効化メソッドの呼び出しに変わる
- [ ] #2 befoldTests/ViewerRendererZoomIntegrationTests.swift:66 の直接代入が消える
- [ ] #3 swift build / swift test が通り、swiftlint のベースライン差分がゼロ
<!-- AC:END -->
