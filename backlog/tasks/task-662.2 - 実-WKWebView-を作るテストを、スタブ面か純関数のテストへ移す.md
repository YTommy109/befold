---
id: TASK-662.2
title: 実 WKWebView を作るテストを、スタブ面か純関数のテストへ移す
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 04:29'
updated_date: '2026-09-29 05:56'
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
- [x] #1 上記の各テストについて、実 WebView を残す／スタブへ移す／純関数へ移すの判断を Notes に記録し、実 WebView の生成回数を変更前後で数えている
- [x] #2 統合テストから単体テストへ移したケースは、守っている修正を戻すと移行後のテストが落ちることを確認している
- [x] #3 実 WebView を残した統合テストが CI で 3 回連続緑である
- [x] #4 変更前後で対象スイートの所要時間（--filter で直列）と全体の swift test wall を測り、Notes に記録している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 変更前の対象スイート直列 ×3・全体並列 ×2 を計測（.tmp/662-2/before）
2. OneShot: BuildsWebView のアサートを AwaitsRenderCompletion へ統合、messageHandlerNames は ViewerWebViewCoordinatorTests と重複なので削除。HandsCanvas は既存の純関数テスト（ViewerCanvasOwnershipTests.documentOwnsCanvasOnlyForHTMLDocuments）に任せ、reject 経路を .html にして drawsBackground の配線を 1 件で見る
3. ContentUpdateIntegration: abortedRender 以外の 4 件をスタブ面 + surfaceDidFinishLoad へ移し ViewerRendererContentUpdateTests 側へ。codeFont 注入は userScriptSources の直接テストへ
4. userScriptSources を internal にし、spaceScroll / codeFont を実 WebView 無しで測る
5. DocumentSurfaceStack の needsWebSurface を 3 入力の static 純関数へ出し引数化テスト。階層確認は PDF の 1 件だけ残し固定 sleep を撤去
6. ロードしない WKWebView() をスタブ面へ（Visibility / ContentUpdate / ReadinessGate / CanvasOwnership）。enter の canvas は RenderSurfaceDispatchTests と重複なので削除。ナビゲーション写像は WKWebView を 1 個共有
7. 移した単体テストは修正を戻して落ちることを確認
8. 変更後を同条件で計測し Notes へ。CI 3 回連続緑
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 判断（実 WebView を残す／スタブへ／純関数へ）と生成数

| テスト | 判断 | 実 WebView 生成（前→後） |
|---|---|---|
| OneShotIntegration BuildsWebViewAndReportsReject | 削除。rejectReason nil・webView 同一性は AwaitsRenderCompletion へ統合、messageHandlerNames は ViewerWebViewCoordinatorTests と重複 | 1→0 |
| OneShotIntegration HandsCanvasToHTMLDocumentsOnly | 削除。判定は既存の純関数テスト documentOwnsCanvasOnlyForHTMLDocuments、配線は ReportsRejectForBinary を .html にして drawsBackground を実物で 1 件見る | 2→0 |
| OneShotIntegration ReportsRejectForBinary / AwaitsRenderCompletion | 実 WebView に残す | 2→2 |
| ContentUpdateIntegration directHTMLExit / diffStateIsNotConfirmed / staleImageEmbed / pendingDiffHolds | スタブ面 + surfaceDidFinishLoad へ移し ViewerRendererRenderRaceTests（新規）へ | 4→0 |
| ContentUpdateIntegration surfaceConstructionInjectsCodeFontScripts | userScriptSources を直接測る形で ViewerWebViewCoordinatorTests へ | 1→0 |
| ContentUpdateIntegration abortedRenderDoesNotLeaveOptionsInJS | JS の _mmdViewOptions を読むので実 WebView に残す | 1→1 |
| RendererFeaturesTests makeWebViewInjectsSpaceScrollFlag | userScriptSources（private→internal）を直接測る | 2→0 |
| DocumentSurfaceLazyWebViewTests | needsWebSurface を 3 入力の static 純関数へ出し引数化テスト（6 ケース）。階層は PDF の 1 件（WebView 0 個）だけ残し Task.sleep(200ms)×2 を撤去 | 2→0 |
| Visibility（3）/ ContentUpdateTests（2）/ ReadinessGate（1）/ CanvasOwnership exit（1） | スタブ面へ。canvas の enter は RenderSurfaceDispatchTests と重複のため削除 | 9→0 |
| WebKitSurfaceEventBridgeMappingTests | ブリッジは引数を読まない（RenderDiagnostics.id のみ）ので static な 1 個を共有 | 10→1 |
| SurfaceConstructionOrderTests | 構成順序そのものが対象なので残す | 2→2 |

合計 **35→6 個**。うち viewer.html のロード完了まで待つもの 9→2。

## 修正を戻して落ちることの確認（AC #2、.tmp/662-2/mutate.py）
11 変異すべてで対象テストが落ちた: TASK-68（離脱分岐の先行確定。exit() がミラーを空にするので exit 呼び出しの後に入れて測った。前に入れた 1 回目は打ち消されて素通りした）、TASK-334（await 前の差分確定）、TASK-224（世代ガード撤去）、TASK-407（pending 見送り撤去）、needsWebSurface の着地種別無視・作成済み無視・View が判定を使わない、spaceScroll 固定 true、codeFont 非注入、exit で canvas を戻さない、OneShot の canvas 配線撤去。

## 計測（AC #4、手元 M 系 / debug / 2026-09-29）
- 対象スイート直列（--no-parallel --filter、3 回）: 前 53 件 2.08 / 2.02 / 1.99 秒 → 後 48 件 0.61 / 0.60 / 0.59 秒（後は移行先 ViewerRendererRenderRaceTests を含む）
- 全体 swift test 並列（2 回）: 前 2021 件 42.4 / 42.7 秒 → 後 2017 件 42.8 / 45.3 秒。**全体 wall は誤差範囲で短縮は観測できなかった**。律速はメインキューに並ぶ ~1900 件の @MainActor テストの総量で、実 WebView 29 個分では動かない（TASK-662 の見立てどおり、効くのは他サブタスクとの合算）

## 対象外として残したもの
- WebKitRenderSurface.make(for:) が codeFont を surfaceOptions へ渡す 1 行の転送は、実 WebView を作るテストでしか見られないため直接の担保を外した（surfaceOptions→userScriptSources は担保あり）
- swiftlint: main 46 件 / HEAD 46 件で新規ゼロ

## CI（AC #3）
PR #703 run 36525076672 の attempt 1〜3 で、実 WebView を残したスイート（ViewerRendererOneShotIntegrationTests / ViewerRendererContentUpdateIntegrationTests / SurfaceConstructionOrderTests / WebKitSurfaceEventBridgeMappingTests）と移行先（ViewerRendererRenderRaceTests / DocumentSurfaceLazyWebViewTests）は default・strict の両ジョブで 3 回連続緑。
ただし strict ジョブ全体は 3/3 で赤。落ちたのは毎回 DistributedAckWaiterIntegrationTests / CLIRequestWireIntegrationTests の 2 件（このタスクでは触っていない）。変更を 3 グループのどれか 1 つだけ戻した使い捨て PR #704〜#706 はすべて緑で、特定のテストではなくタイミングのずれで顕在化した既知の間欠失敗（TASK-622 Notes で 1 回観測済み）。原因と実測は TASK-664 に記録し、PR #703 のマージは TASK-664 に塞がれている。

native-app-design.md: テストの置き換えと、needsWebSurface を同じ判定のまま static 関数へ出しただけで仕様は変わらないため更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
実 WKWebView を作っていたテストのうち、Swift 側のミラーや注入スクリプトの文字列しか見ていないものを、スタブ面（ViewerRendererMessageStubs.Surface + surfaceDidFinishLoad）と純関数（userScriptSources / DocumentSurfaceStack.needsWebSurface）のテストへ移した。対象テストの実 WebView 生成は 35→6 個、ロード完了待ちは 9→2 個。移したテストは守っている修正を 1 つずつ戻す変異 11 件ですべて落ちることを確認した。対象スイートの直列実行は 2.0 秒→0.6 秒。全体の並列 wall は 42.4/42.7 秒→42.8/45.3 秒で誤差範囲、短縮は観測できなかった（律速はメインキュー全体）。実 WebView を残した統合テストは CI で 3 回連続緑だが、strict ジョブは既知の Distributed Notification 系 2 件（TASK-664）で落ちており、PR #703 のマージは TASK-664 待ち。swiftlint は main との差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
