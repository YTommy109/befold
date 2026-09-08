---
id: TASK-599
title: >-
  TASK-595 の後始末: RenderSurface 抽象が `as? WebKitRenderSurface` で漏れ、遮断と後始末が黙って
  no-op になる
status: To Do
assignee: []
created_date: '2026-09-08 14:16'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 871000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-595 で `RenderSurface` 境界を入れたが、Kit の内側に実装型への downcast が 3 箇所残っており、いずれも「WebKit 実装でなければ何もしない」形で fail-open している。

1. `ViewerWebViewFactory.loadViewerHTML(into:)` — `guard let webKitSurface = surface as? WebKitRenderSurface else { surface.loadLocalFile(...); return }`。`RemoteLoadBlocker` の doc は「ここが app / QuickLook / 直接 HTML モードすべての唯一の入口なので、適用点をここに一本化すると『ブロッカ未適用のまま文書が描かれる』余地が構造的に無くなる」と書いているが、この downcast でその構造的保証が条件付きに戻った。ルールリストは configuration に載るので viewer.html ロード時の 1 回で以後の直接 HTML ロード（外部 .html の `loadLocalFile` / `loadHTML`）まで守っている。WebKit 以外の面が入るとその 1 回が丸ごと飛び、http(s)/ws(s) へのリモート取得が層ごと外れる。
2. `ViewerRenderer.dismantle(_:)` — `(surface as? WebKitRenderSurface)?.dismantle(features:)`。postMessage ハンドラの解除が黙って行われない。
3. `ViewerWebView.makeNSView` — downcast に失敗すると `preconditionFailure` でアプリが落ちる。`makeWebView` が `WKWebView` を返していたときはコンパイル時に保証されていたものが、実行時クラッシュへ変わった。

現時点の実害はゼロ（本番・テストとも面は常に `WebKitRenderSurface`）。ただし「描画エンジンを差し替え可能にする」という TASK-595 の目的そのものを達成した瞬間に、遮断と後始末が無言で外れる。CLAUDE.md の「決めたことには、破れたら落ちるものを付ける」に照らして、判断を構造かテストのどちらかで担保したい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer.html のロード経路で RemoteLoadBlocker が必ず適用されることが、面の実装型に依らず担保されている（`RenderSurface` 側の口へ寄せる／適用漏れで落ちるテストを置く、のいずれか）
- [ ] #2 postMessage ハンドラの解除が、面の実装型に依らず行われる（または解除できない型が渡ったことが検知できる）
- [ ] #3 `ViewerWebView.makeNSView` の downcast 失敗が `preconditionFailure` 以外の形で扱われている、または downcast 自体が不要になっている
- [ ] #4 Kit 内の `as? WebKitRenderSurface` の残存箇所を数え、残すものには残す理由が doc コメントに書かれている
<!-- AC:END -->
