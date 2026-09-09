---
id: TASK-602
title: 'TASK-595 の後始末: `renderOnce` の未使用引数と、実態に合わなくなった doc コメント'
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 14:17'
updated_date: '2026-09-08 14:57'
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
- [x] #1 `renderOnce` の `surface` 引数が使われている、または削除されている
- [x] #2 `ViewerRenderer.surfaceEventBridge` / `WebKitRenderSurface` の doc が実在するシンボルだけを指している
- [x] #3 WKWebView 生成の「唯一の入口」がどこかについて、doc と .swiftlint.yml のメッセージが同じことを言っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（2026-09-08）

### AC#1: `renderOnce` の引数を実際に使う
評価クロージャの捕捉を `[weak self]` → `[weak surface]` に変え、`self?.surface` の読み直しをやめた。これで**描画が呼び出し時点の面に固定される**（旧実装の `[weak webView]` と同じ意図）。同じ `OneShotRenderer` で `load` が 2 回呼ばれても、1 回目の飛行中の評価が 2 回目の面へ当たらない。weak のままにしたのは、面が捨てられた後まで生かさないため。

### AC#2 / AC#3: doc の実態合わせ（起票時の 3 件 + 自分で増やした 3 件）
起票時に挙がっていた 3 件に加え、**TASK-599 で `makeSurface` を撤去した際に doc 参照を 3 箇所取り残していた**ことが着手時の grep で判明した（この task と同種の欠陥を自分で作っていた）。テスト側にも 2 件あり、計 8 件を直した。

- `ViewerRenderer.surfaceEventBridge`: 「makeWebView が…設定する」→ `WebKitRenderSurface.make`
- `WebKitRenderSurface` ヘッダ: 「生成は `ViewerRenderer.webView` の setter 1 箇所」→ 実態（`make(for:…)` と、テストの直接生成。レンダラ側の状態を書くのは `adopt`）
- `surfaceOptions` / `adopt` / `dismantle` の doc から `makeSurface` を除去
- `ViewerRendererMessageStubs` と `RenderSurfaceDispatchTests` のコメントからも除去

**AC#3（「唯一の入口」の食い違い）**は、2 つが別のことを言っていると明記して解消した。`WKWebView` そのものを組み立てるのは `ViewerWebViewFactory`（`.swiftlint.yml` の `webview_creation_outside_webkit_layer` が守る規約）、呼び出し側から見た入口が `WebKitRenderSurface.make`。**組み立ての置き場と、呼び出しの入口**という区別を doc に書いた。

### 担保について
`renderOnce` の修正には回帰テストを付けていない。2 回 `load` する経路の再現には実 WebView 2 面と非同期の飛行中状態が要り、環境依存のテストになる（CLAUDE.md の「環境に依存する実測値をアサートしない」に触れる）。代わりに**捕捉リストで意図を構造化**した——`self?.surface` へ戻すには捕捉リストを書き換える必要があり、差分で見える。

### 検証（実測）
- `swift test` **1929 tests / 318 suites すべて pass**
- `/webview-smoke` **PASS**（exit 0）
- `xcodebuild build -scheme befold` **BUILD SUCCEEDED**
- swiftlint ベースライン: main 51 / HEAD 51、真の新規 **0 件**
- 起票後に `grep` で「実在しないシンボルへの参照」が 0 件になったことを確認

### 起票ファイルの誤アーカイブ
着手時、`backlog/archive/tasks/` に `status: To Do` のまま入っていた（PR #642 の中で誤って移動していた）。`git mv` で `backlog/tasks/` へ戻してから着手している。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
renderOnce の評価クロージャを [weak self] から [weak surface] へ変え、描画を呼び出し時点の面に固定した（同じインスタンスで load が 2 回呼ばれたとき、1 回目の飛行中の評価が 2 回目の面へ当たる問題）。実態に合わなくなった doc は起票時の 3 件に加え、TASK-599 で makeSurface を撤去した際の取り残し 3 件とテスト側 2 件が grep で見つかり、計 8 件を修正。「WKWebView を作る唯一の入口」の食い違いは、組み立ての置き場（ViewerWebViewFactory）と呼び出しの入口（WebKitRenderSurface.make）という別のことを言っていると明記して解消した。swift test 1929 件 pass、/webview-smoke PASS、xcodebuild BUILD SUCCEEDED、swiftlint 新規違反 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
