---
id: TASK-662.2
title: 実 WKWebView を作るテストを、スタブ面か純関数のテストへ移す
status: To Do
assignee: []
created_date: '2026-09-29 04:29'
labels: []
dependencies: []
parent_task_id: TASK-662
priority: high
ordinal: 858000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
並列実行の律速はメインキュー（TASK-662 の実測）。実 WKWebView の生成・ロードは MainActor を長く占有し、TASK-607 の「実 WebView 統合テストが飢える」問題も悪化させる。検証内容が Swift 側のミラーや文字列だけのテストまで実 WebView を作っている。

## 該当（レビューで確認した箇所）
- `ViewerRendererOneShotIntegrationTests`: 実ロード 4 回。`loadOneShotBuildsWebViewAndReportsReject` のアサートは `loadOneShotAwaitsRenderCompletion` へ移せる／`messageHandlerNames` は `ViewerWebViewCoordinatorTests` と重複。`loadOneShotHandsCanvasToHTMLDocumentsOnly` は純関数 `ViewerWebViewFactory.documentOwnsCanvas(fileType:isSourceMode:)` の引数化テスト + reject 経路での配線確認 1 件で足りる（`OneShotRenderer.load` の reject 経路も `setDocumentOwnsCanvas` を通る）
- `ViewerRendererContentUpdateIntegrationTests`: 6 件中 5 件が実ロード。`diffStateIsNotConfirmedBeforeRender` / `staleImageEmbedDoesNotClobberNewerRender` / `pendingDiffHoldsPreviousFrameUntilResolved`（おそらく `directHTMLExitSurvivesRaceDuringReload` も）は `renderer.rendered.*` しか見ていない。`ViewerRendererZoomProjectionTests` が TASK-607 で採った形（`ViewerRendererMessageStubs.Surface` + `navigationCoordinator.surfaceDidFinishLoad()`）へ移せる。JS の `_mmdViewOptions` を読む `abortedRenderDoesNotLeaveOptionsInJS` だけ実 WebView に残す。上限なしの `Task.yield` スピン（`waitForWebViewLoad`）も MainActor を占有している
- `RendererFeaturesTests.makeWebViewInjectsSpaceScrollFlag`: user script の文字列を見るだけなのに `WebKitRenderSurface.make` で実 WebView を 2 つ作り `loadViewerHTML` まで走らせ、後始末しない。`ViewerWebViewFactory.userScriptSources(options:)`（現在 private）を internal にして直接測れる
- `DocumentSurfaceLazyWebViewTests`: 実 WKWebView を NSHostingView 経由で生成し、`Task.sleep(200ms)` を 2 回固定で待ち、`static var retained` でプロセス終了まで保持する。判定（`DocumentSurfaceStack` の `needsWebSurface` / `isOpeningPDF`）は 3 入力の純関数に出せる。階層に出る確認は 1 件だけ残し、固定待ちは条件待ちへ
- ロードしない `WKWebView()` の生成: `ViewerRendererVisibilityTests`、`ViewerRendererContentUpdateTests`（2 箇所）、`ViewerReadinessGateTests`、`ViewerCanvasOwnershipTests`（2 箇所）、`SurfaceNavigationPolicyTests` / `WebKitSurfaceEventBridgeMappingTests`（`mapKind` 1 回ごとに生成、約 10 個。ブリッジは引数を使っていない）。`ViewerRendererMessageStubs.Surface` へ置き換えるか、1 個を使い回す。`drawsBackground` を実物で見るのは 1 件だけ残す
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 上記の各テストについて、実 WebView を残す／スタブへ移す／純関数へ移すの判断を Notes に記録し、実 WebView の生成回数を変更前後で数えている
- [ ] #2 統合テストから単体テストへ移したケースは、守っている修正を戻すと移行後のテストが落ちることを確認している
- [ ] #3 実 WebView を残した統合テストが CI で 3 回連続緑である
- [ ] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->
