---
id: TASK-514
title: appliedPageZoom の書き込み入口を 1 つに閉じる
status: Done
assignee: []
created_date: '2026-08-18 02:54'
updated_date: '2026-08-18 03:01'
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
- [x] #1 appliedPageZoom（相当の値）への書き込みが新しい型の中に閉じ、DirectHTMLModeController は無効化メソッドの呼び出しに変わる
- [x] #2 befoldTests/ViewerRendererZoomIntegrationTests.swift:66 の直接代入が消える
- [x] #3 swift build / swift test が通り、swiftlint のベースライン差分がゼロ
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
PageZoomProjector（BefoldRenderKit/PageZoomProjector.swift）へ desired / applied / applyIfReady を切り出した。applied は private(set) + invalidateApplied() のみで無効化する（rendered ミラーの recordRendered と同じ構造）。ViewerRenderer.initialPageZoom は pageZoom.desired への転送プロパティとして公開名のまま残し、ホスト（ViewerWebView / QuickLook）側の変更はゼロ。DirectHTMLModeController の 2 箇所は renderer.pageZoom.invalidateApplied() へ、initialPageZoom 読みは pageZoom.desired へ、ViewerNavigationCoordinator は pageZoom.applyIfReady(assumingReady: true) へ変更。検証: swift build 成功 / swift test 1632 tests・260 suites すべて成功 / swiftlint は origin/main を git archive で別ディレクトリへ展開して比較し 54 件対 54 件で差分ゼロ / swiftformat は 0 files formatted。docs/dev/native-app-design.md は appliedPageZoom に言及がなく（rg で 0 件）、公開 API も変わらないため更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
appliedPageZoom を PageZoomProjector へ切り出し、書き込み入口を invalidateApplied() の 1 つに閉じた。DirectHTMLModeController とテストからの直接代入は消滅。swift build / swift test（1632 tests 全通過）/ swiftlint ベースライン差分ゼロで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
