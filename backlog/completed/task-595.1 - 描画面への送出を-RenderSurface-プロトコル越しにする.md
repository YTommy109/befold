---
id: TASK-595.1
title: 描画面への送出を RenderSurface プロトコル越しにする
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 13:22'
updated_date: '2026-09-08 13:38'
labels: []
dependencies: []
parent_task_id: TASK-595
ordinal: 868000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-595 の 1/3（送出方向）。

BefoldRenderKit が WKWebView へ**送る**操作をプロトコル境界の内側へ入れる。探索の実測では、この層が実際に使っている送出操作は 7 つに収まる（WKWebView の API を写したものではない）。

| 操作 | なぜ要るか |
| --- | --- |
| evaluateScript(_:completion:) | 描画コマンドの送出。Kit 内 5 箇所すべてが返り値を使っていないので、返すのはエラーのみ |
| callScript(_:) async throws -> Any? | 初回描画の完了を待つ唯一の経路（callAsyncJavaScript）。Kit 内で await が要るのはここだけ |
| loadLocalFile(_:allowingReadAccessTo:) | viewer.html のロードと直接 HTML モード |
| loadHTML(_:mimeType:encoding:baseURL:) | charset 宣言の無い HTML を UTF-8 明示でロード |
| zoom (get/set) | 直接 HTML モードの前後で倍率を維持 |
| currentURL (get) | リンククリックの同一文書判定 |
| isContentJavaScriptEnabled (set) | 直接 HTML モードで JS を切り、戻すときに入れ直す |

**evaluateScript を async にしないこと（親タスクの /review-design 指摘 F1）。** ViewerScriptDispatcher.applyRender は await の後を await 無しの一続きに保っており、これは TASK-320 / 334 / 336 で 3 連鎖した「描画ミラーの確定漏れ」を構造で塞いだ結果。async にすると同型の 4 件目を招く。

この段では ViewerRenderer が WKWebView を保持したままでよい（解消は 595.3）。受信方向（WKNavigationDelegate / WKScriptMessageHandler）は 595.2 で扱う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BefoldRenderKit に RenderSurface プロトコル（@MainActor）があり、提供する操作それぞれに「なぜこの層が必要とするか」の doc コメントが付いている
- [x] #2 evaluateScript が同期・fire-and-forget で、返り値はエラーのみ（async ではない）。その理由が doc コメントで示されている
- [x] #3 ViewerScriptDispatcher / PageZoomProjector / ReferenceResolutionQueue / ViewerRenderer+RenderHelpers / DirectHTMLModeController が WKWebView 型ではなく RenderSurface 越しに送出している
- [x] #4 WKWebView 実装が 1 つの型に閉じている
- [x] #5 fake の RenderSurface 実装を使い、WKWebView 実体なしに描画コマンドの送出順序を検証するテストが 1 つ以上ある（TASK-595 の AC#4 をここで満たす）
- [x] #6 swift test が通り、/webview-smoke が PASS する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 実装方針

### プロトコル `RenderSurface`（@MainActor）— 8 操作
親タスクの表の 7 つに `setDocumentOwnsCanvas(_:)` を足す。`drawsBackground` の KVC 切り替えは構成ではなく**実行時の切り替え**（直接 HTML モードの enter/exit と対で倒す）なので境界に出す。

### 単一の真実の源を壊さない配線
`ViewerRenderer` は `surface: (any RenderSurface)?` を **stored** で持ち、既存の `public var webView: WKWebView?` を **computed accessor** にする。

    public var surface: (any RenderSurface)?
    public var webView: WKWebView? {
        get { (surface as? WebKitRenderSurface)?.webView }
        set { surface = newValue.map(WebKitRenderSurface.init) }
    }

こうすると状態は `surface` の 1 つだけで、`webView` の二重管理が生まれない。既存の呼び出し元（OneShotRenderer・テスト・makeWebView）は無変更で通り、595.3 で `webView` を消せば移行が終わる。

### `WebKitRenderSurface` は struct
WKWebView 参照を包むだけの値型にする。状態を持たないので、computed から都度作っても同一性の問題が起きない（stored にすると `webView` との二重管理になる）。

### fake（AC#5）
`surface` が stored なので、テストは `renderer.surface = FakeRenderSurface()` で差し替えられる。既存の `ViewerRendererMessageStubs.WebView`（WKWebView のサブクラス）は実体生成が要るが、fake は要らない。

## /review-design（595.1 分・2026-09-08）
親タスクのレビューで確定した F1・F5・F6 がそのまま効く。加えてこの段固有の点:

- [項目2] `evaluateScript` は同期・fire-and-forget（F1）。`callScript` だけ async にするのは OneShotRenderer が初回描画の完了を待つ唯一の経路だから。**2 つを 1 つにまとめない**（まとめると全送出が async になり F1 を破る）。
- [項目3] 送出箇所は実測 5 ファイル（ViewerScriptDispatcher / PageZoomProjector / ReferenceResolutionQueue / ViewerRenderer+RenderHelpers / OneShotRenderer）＋ DirectHTMLModeController のロード・倍率。`ViewerWebViewFactory.loadViewerHTML` も surface 経由へ通す（bundle 解決は factory に残す）。
- [項目5] `webView` を computed にすることで、setter 経由の代入（テスト 5 箇所・makeWebView）が `surface` の更新に化ける。順序依存は無い（どちらも代入 1 回）。
- [項目9] 「WKWebView 実装は 1 つの型に閉じる」の担保は **595.3 で入れる**（この段ではまだ ViewerWebViewFactory 等が WKWebView に触るため、今入れると例外リストが本体になる）。595.3 の AC に入れてある。
- [項目10] `ViewerRenderer` 型グループは 351 行（閾値 400）。computed の `webView` と stored の `surface` で +8 行程度。新規 2 ファイルは別グループ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（2026-09-08）

### 追加
- `BefoldRenderKit/RenderSurface.swift`: 8 操作のプロトコル（@MainActor）。各操作に「なぜこの層が必要とするか」を doc で明記。
- `BefoldRenderKit/WebKitRenderSurface.swift`: WKWebView 実装。`drawsBackground` の KVC もここへ閉じた。
- `befoldTests/RenderSurfaceDispatchTests.swift`: fake による送出経路のテスト 3 件。
- `ViewerRendererMessageStubs.Surface`: WKWebView 実体を作らない fake。

### 単一の真実の源
`ViewerRenderer.surface` を stored にし、`webView` を computed accessor（getter は `surface as? WebKitRenderSurface` の実体、setter は `surface` を更新）にした。状態は `surface` 1 つだけで、二重管理が無い。既存の呼び出し元（OneShotRenderer・テスト・makeWebView）は無変更で通る。

### 変換した送出箇所
ViewerScriptDispatcher / PageZoomProjector / ReferenceResolutionQueue / ViewerRenderer+RenderHelpers / ViewerRenderer+ContentUpdate / DirectHTMLModeController / ViewerNavigationCoordinator / ViewerWebViewFactory.loadViewerHTML。

### 実装バグを 1 件、既存テストが捕まえた
`WebKitRenderSurface.setDocumentOwnsCanvas` で `drawsBackground` の極性を反転させて書いてしまい、`ViewerCanvasOwnershipTests` の 2 件が落ちた。元実装（`ViewerWebViewFactory.setDocumentOwnsCanvas`）は**同極性**で、`drawsBackground == true` が「WebKit が地を塗る = 文書が canvas を所有」と意味が一致している。反転を戻し、二度と反転させないよう理由を doc コメントに書いた。

### 検証（実測）
- `swift test` **1926 tests / 316 suites すべて pass**
- 新規テスト 3 件は **0.001 秒**で完了（WebKit プロセスが立たないことの実証）。**規則を壊すと落ちることを実測**: 表示オプションの送出を本文の後ろへ移すと「描画は表示オプションを本文より先に送る」が `(lineNumbersIndex → 2) < (renderIndex → 1)` で失敗し、戻すと通る
- `/webview-smoke` **PASS**（exit 0）
- `xcodebuild build -scheme befold` **BUILD SUCCEEDED**
- swiftlint ベースライン: main 51 / HEAD 51、真の新規 **0 件**
- swiftformat 実行後の差分なし

### WebKit 依存の推移（親タスク AC#3 の中間値）
| 指標 | before | 595.1 後 |
| --- | --- | --- |
| `import WebKit` を含むファイル | 15 | **13** |
| `WKWebView` に言及するファイル | 11 | **9** |

残りは 595.2（受信方向）と 595.3（生成・破棄）で減らす。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
描画面への送出を RenderSurface プロトコル（8 操作・@MainActor）越しにした。evaluateScript は同期・fire-and-forget で、async にしない理由（TASK-320 / 334 / 336 で 3 連鎖した描画ミラーの確定漏れ）を doc に明記。ViewerRenderer は surface を唯一の状態として持ち、webView はそこから導く accessor にしたので二重管理が無い。fake による送出経路のテスト 3 件を追加し、WKWebView 実体なしに 0.001 秒で回ることと、順序規則を壊すと落ちることを実測した。実装中に drawsBackground の極性を反転させるバグを入れたが既存の ViewerCanvasOwnershipTests が捕まえ、理由つきで修正済み。swift test 1926 件 pass、/webview-smoke PASS、xcodebuild BUILD SUCCEEDED、swiftlint 新規違反 0 件。WebKit 依存は import 15→13 / WKWebView 言及 11→9。
<!-- SECTION:FINAL_SUMMARY:END -->
