---
id: TASK-600
title: '`surfaceDidFinishLoad` が surface 未設定だと readiness ゲートを永久に開かない'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 14:17'
updated_date: '2026-09-08 14:24'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 872000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-595.2 で `ViewerNavigationCoordinator.webView(_:didFinish:)` を `surfaceDidFinishLoad()` へ置き換えた際、旧実装がデリゲート引数の `webView` を使っていた箇所を `renderer.surface` の読み出しへ移し、それを guard の条件に併合した。

```swift
func surfaceDidFinishLoad() {
    guard let renderer, let surface = renderer.surface else { return }
    renderer.directHTML.applyPendingZoom(to: surface)
    renderer.pageZoom.applyIfReady(assumingReady: true)
    renderer.readiness.markReady()
}
```

旧実装では `guard let renderer else { return }` だけで、`markReady()` は `renderer.webView` の有無に依存しなかった。`surface` を必要とするのは `applyPendingZoom(to:)` の 1 行だけなのに、いま `surface == nil` だと `markReady()` まで飛ばされる。`ViewerReadinessGate` は 1 度も ready にならず、`runWhenReady` に積まれた描画要求が全部落ちたまま窓が白いままになる（`applyIfReady` も同じ guard で弾かれるので倍率も当たらない）。

本番で `renderer.surface` が nil になる経路は現時点では無い（`makeSurface` / `adopt` が同期区間で必ず入れる）ため実害は未観測。ただし `surface` は `public var` で外から nil を入れられるうえ、`WebKitRenderSurface.make` は `adopt` より先に viewer.html のロードを始める（`RemoteLoadBlocker` のルールリストがキャッシュ済みだと `apply` は同期で completion を呼ぶ）ので、順序の余白が実在する。ゲートを開けないという故障は「倍率が当たらない」より重い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `surfaceDidFinishLoad` で `renderer.surface` が nil でも `readiness.markReady()` が呼ばれる（surface を要るのは `applyPendingZoom` だけに閉じる）
- [x] #2 surface が nil のまま didFinish が届いても readiness ゲートが開くことを見るテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 修正と検証（2026-09-08）

surface を要る 1 行（`applyPendingZoom(to:)`）だけを `if let` に閉じ、`guard` は main と同じ `guard let renderer` へ戻した。`markReady()` と `applyIfReady` は surface の有無に依存しない。

担保として `SurfaceReadinessGateTests` を追加（`RenderSurfaceDispatchTests.swift` 内）。surface を入れずに `runWhenReady` を積み、`surfaceDidFinishLoad()` で走ることを見る。

**修正を戻すと落ちることを実測**: guard を併合した形へ戻すと `Expectation failed: didRender` で失敗し、戻すと通る。通っただけのテストになっていない。

検証: `swift test` **1927 tests / 317 suites すべて pass**、`/webview-smoke` PASS（exit 0）、swiftlint ベースライン main 51 / HEAD 51 で真の新規 0 件。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
surface を必要とする applyPendingZoom の 1 行だけを if let に閉じ、readiness ゲートを surface の有無から切り離した。TASK-595.2 で guard へ併合してしまった自己回帰で、マージ前に修正済み。SurfaceReadinessGateTests が担保し、修正を戻すと Expectation failed: didRender で落ちることを実測した。swift test 1927 件 pass、/webview-smoke PASS、swiftlint 新規違反 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
