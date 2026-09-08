---
id: TASK-602
title: 'TASK-595 の後始末: `renderOnce` の未使用引数と、実態に合わなくなった doc コメント'
status: To Do
assignee: []
created_date: '2026-09-08 14:17'
labels: []
dependencies: []
priority: low
type: chore
ordinal: 874000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-595 の 3 サブタスクで置き換えた際に取り残された小さなずれ。

**1. `OneShotRenderer.renderOnce(surface:render:)` の `surface` 引数が未使用。** 中の評価クロージャは `[weak self]` を捕まえて `self?.surface`（= `renderer.surface`）を読み直しており、引数を一度も使っていない。旧実装は `[weak webView]` でその回の webView を捕まえていたので、描画対象が呼び出し時点の面に固定されていた。いまは `load` が同じインスタンスで 2 回呼ばれると（`load` は public、`PreviewViewController` はコントローラを再利用しうる）、1 回目の飛行中の評価が 2 回目の面へ当たる。引数を使うか、引数を消して意図を明示するかのどちらかにしたい。

**2. 実在しないシンボルを指す doc コメントが 3 箇所。**
- `ViewerRenderer.swift` の `surfaceEventBridge` の doc: 「makeWebView が navigationDelegate と postMessage ハンドラの両方にこれを設定する」— `ViewerRenderer.makeWebView` は無くなり、設定するのは `WebKitRenderSurface.make`。
- `WebKitRenderSurface.swift` のヘッダ: 「生成は `ViewerRenderer.webView` の setter 1 箇所だけで、そこが唯一の状態（`surface`）を更新する」— `webView` の setter は存在しない。`surface` を書くのは `ViewerRenderer.adopt`（`makeSurface` と `OneShotRenderer.load` の 2 経路から呼ばれる）と public var への直接代入。
- `WebKitRenderSurface.make` の doc は自分を「**WKWebView を作る唯一の入口**」と呼ぶが、`.swiftlint.yml` の新ルールのメッセージは「WKWebView を作るのは ViewerWebViewFactory だけ」で、どちらが規約なのか読み手に伝わらない。

`scripts/check-doc-symbols.sh` は CLAUDE.md しか見ないので、この種のずれは自動検出されない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `renderOnce` の `surface` 引数が使われている、または削除されている
- [ ] #2 `ViewerRenderer.surfaceEventBridge` / `WebKitRenderSurface` の doc が実在するシンボルだけを指している
- [ ] #3 WKWebView 生成の「唯一の入口」がどこかについて、doc と .swiftlint.yml のメッセージが同じことを言っている
<!-- AC:END -->
