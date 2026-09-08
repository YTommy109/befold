---
id: TASK-595.1
title: 描画面への送出を RenderSurface プロトコル越しにする
status: To Do
assignee: []
created_date: '2026-09-08 13:22'
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
- [ ] #1 BefoldRenderKit に RenderSurface プロトコル（@MainActor）があり、提供する操作それぞれに「なぜこの層が必要とするか」の doc コメントが付いている
- [ ] #2 evaluateScript が同期・fire-and-forget で、返り値はエラーのみ（async ではない）。その理由が doc コメントで示されている
- [ ] #3 ViewerScriptDispatcher / PageZoomProjector / ReferenceResolutionQueue / ViewerRenderer+RenderHelpers / DirectHTMLModeController が WKWebView 型ではなく RenderSurface 越しに送出している
- [ ] #4 WKWebView 実装が 1 つの型に閉じている
- [ ] #5 fake の RenderSurface 実装を使い、WKWebView 実体なしに描画コマンドの送出順序を検証するテストが 1 つ以上ある（TASK-595 の AC#4 をここで満たす）
- [ ] #6 swift test が通り、/webview-smoke が PASS する
<!-- AC:END -->
