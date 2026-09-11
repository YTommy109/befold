---
id: TASK-599
title: >-
  TASK-595 の後始末: RenderSurface 抽象が `as? WebKitRenderSurface` で漏れ、遮断と後始末が黙って
  no-op になる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 14:16'
updated_date: '2026-09-08 14:49'
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
- [x] #1 viewer.html のロード経路で RemoteLoadBlocker が必ず適用されることが、面の実装型に依らず担保されている（`RenderSurface` 側の口へ寄せる／適用漏れで落ちるテストを置く、のいずれか）
- [x] #2 postMessage ハンドラの解除が、面の実装型に依らず行われる（または解除できない型が渡ったことが検知できる）
- [x] #3 `ViewerWebView.makeNSView` の downcast 失敗が `preconditionFailure` 以外の形で扱われている、または downcast 自体が不要になっている
- [x] #4 Kit 内の `as? WebKitRenderSurface` の残存箇所を数え、残すものには残す理由が doc コメントに書かれている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化の検討（CLAUDE.md「調査後・実装前の単純化検討」）

3 つの downcast はいずれも「**プロトコルに操作が足りない**」ことの現れ。分岐や状態を足して塞ぐのではなく、足りない操作を境界へ出せば downcast ごと消える。

| downcast | 足りない操作 | 置き換え |
| --- | --- | --- |
| `loadViewerHTML` の `as?` | 「リモート読み込みの遮断ポリシーを適用する」 | `applyRemoteLoadPolicy(then:)` を `RenderSurface` へ |
| `dismantle` の `as?` | 「名前つき postMessage ハンドラを外す」 | `removeMessageHandlers(named:)` を `RenderSurface` へ |
| `makeNSView` の `as?` | （不要）アプリ側が実装型を作ればよい | `OneShotRenderer` と同じく `WebKitRenderSurface.make` + `adopt` |

**これで fail-open が fail-closed になる**のではなく、**呼び出しが無条件になる**のが要点。新しい描画エンジンは 2 操作を実装しないとコンパイルが通らないので、「黙って外れる」経路が構造的に消える（空実装を書くのは意図的な選択として残る）。

`removeMessageHandlers(named:)` はハンドラ名の配列で受ける。`RendererFeatures` を境界の語彙に持ち込まず、操作を具体的に保つため（名前の算出は `ViewerWebViewFactory.messageHandlerNames(for:)` のまま呼び出し側）。

## 手順
1. `RenderSurface` へ 2 操作を追加（doc に「なぜこの層が要るか」）。
2. `WebKitRenderSurface` が実装（`RemoteLoadBlocker.apply` と `removeScriptMessageHandler` をここへ閉じる）。
3. `ViewerWebViewFactory.loadViewerHTML` / `ViewerRenderer.dismantle` から downcast を撤去。
4. `ViewerWebView.makeNSView` を `WebKitRenderSurface.make` + `adopt` へ（preconditionFailure ごと消える）。
5. テストの fake が 2 操作を実装し、`applyRemoteLoadPolicy` が**必ず呼ばれること**を見るテストを置く（AC#1 の「適用漏れで落ちる」担保）。
6. 残る `as? WebKitRenderSurface` を数え、残すものに理由を書く（AC#4）。

## /review-design（599 分）
- [項目1] 判定を増やさない。downcast という**型による分岐**を消す方向なので、真実の源は増えも減りもしない。
- [項目2] `RemoteLoadBlocker` の doc が主張する「適用点は 1 箇所」という不変条件を**回復**する変更。fail-open の性質（ルールリストを用意できなくても completion は呼ぶ）は WebKit 実装の内側にそのまま残す。
- [項目3] downcast は実測 6 箇所（本番 4 / テスト 2）。本番 3 つを消し、`OneShotRenderer` の 1 つ（テスト可視化用の `webView` アクセサ）は残して理由を書く。
- [項目5] `makeNSView` の構成順序が変わる（renderer 経由 → アプリが直接構成して adopt）。`OneShotRenderer` が既に同じ順序で動いており、delegate コールバックは非同期なので adopt が後でも安全（レビューで確認済み）。
- [項目9] 担保は「呼び出しが無条件になる」構造そのもの＋ fake で適用を観測するテスト。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（2026-09-08）

### 単純化で downcast ごと消した
3 つの downcast はどれも「プロトコルに操作が足りない」ことの現れだったので、分岐を条件付きで塞ぐのではなく**足りない操作を境界へ出した**。

- `RenderSurface` に `applyRemoteLoadPolicy(then:)` と `removeMessageHandlers(named:)` を追加。
- `ViewerWebViewFactory.loadViewerHTML` と `ViewerRenderer.dismantle` の downcast を撤去。**呼び出しが無条件になった**のが要点で、新しい描画エンジンは 2 操作を実装しないとコンパイルが通らない（空実装を書くのは意図的な選択として残る）。
- `removeMessageHandlers` はハンドラ名の配列で受ける。`RendererFeatures` を境界の語彙に持ち込まないため。
- `ViewerRenderer.dismantle()` は引数を取らず自分の `surface` を使う形へ。登録した面と解除する面がずれる余地を消した。

### 構成経路を 1 本に畳んだ（AC#3）
`ViewerRenderer.makeSurface` を撤去し、`WebKitRenderSurface.make(for:initialZoom:…)` を唯一の構成入口にした。戻り値が具体型なので、アプリ側（`NSViewRepresentable`）の降格そのものが不要になり、`preconditionFailure` も消えた。`OneShotRenderer` も同じ入口を通る。`ViewerRenderer` は WKWebView を知らないまま（入口を WebKit 側の型の static に置いたため）。

### AC#4: 残った downcast は 1 箇所
本番 4 箇所 → **1 箇所**（`OneShotRenderer.webView`）。テストが「内包するレンダラが描画完了まで面を保持し続けている」ことを確かめるためだけの窓で、本番の描画経路は通らない。境界へ出すと「実体の NSView を寄越せ」という WebKit 固有の要求が `RenderSurface` の語彙に混ざるため、理由を doc に書いて残した。

### 検証（実測）
- `swift test` **1929 tests / 318 suites すべて pass**
- **分岐を復活させると落ちることを実測**（担保が空振りでない確認）:
  - `(surface.remoteLoadPolicyApplications → 0) == 1` で失敗
  - `(surface.removedMessageHandlerNames → []) == ["zoomChanged", …7 件]` で失敗
  - 戻すと両方 pass
- `/webview-smoke` **PASS**（exit 0）
- `xcodebuild build -scheme befold` **BUILD SUCCEEDED**
- swiftlint ベースライン: main 51 / HEAD 51、真の新規 **0 件**
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
3 つの downcast を、足りない操作を境界へ出すことで消した。RenderSurface に applyRemoteLoadPolicy と removeMessageHandlers を足し、遮断ポリシーの適用と postMessage ハンドラの解除を無条件の呼び出しにした（実装型で分岐しないので黙って外れない）。構成経路は WebKitRenderSurface.make(for:) 1 本に畳み、戻り値が具体型になったことでアプリ側の降格と preconditionFailure が不要になった。本番の downcast は 4 箇所 → 1 箇所で、残した 1 つには理由を doc に書いてある。分岐を復活させると 2 つのテストが落ちることを実測済み。swift test 1929 件 pass、/webview-smoke PASS、xcodebuild BUILD SUCCEEDED、swiftlint 新規違反 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
