---
id: TASK-595.3
title: 描画面の生成と破棄を実装型へ畳み、ViewerRenderer から WKWebView 型を消す
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 13:23'
updated_date: '2026-09-08 14:03'
labels: []
dependencies:
  - TASK-595.2
parent_task_id: TASK-595
ordinal: 870000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-595 の 3/3（生成・破棄）。ここで親タスクの AC#1 と AC#3 を満たす。

ViewerWebViewFactory（WKWebView の唯一の生成点・configuration 組み立て・user script 注入・message handler 登録/解除・drawsBackground）と RemoteLoadBlocker（WKContentRuleList）を、595.1 で作った WKWebView 実装型の内側へ畳む。これらは実行時の操作ではなく**構成と破棄の関心**なので、プロトコルには出さない。

その上で ViewerRenderer.webView: WKWebView? を抽象型へ置き換え、navigationDelegate の配線も実装型の内側へ移す。

**AC#3 の計測（親タスクの /review-design 指摘 F5）**: 「import WebKit のファイル数」だけで測らない。未使用 import を消すだけで 15→12 に見せられるため（実測: RenderValues / RenderedStateMirror / ViewerRenderer+ContentUpdate の 3 つは import があるだけで WebKit 型を使っていない）、**「WKWebView という型名に言及するファイル数」も併せて測る（着手時 11）**。

**対象外（親タスクの指摘 F3・F4）**: WebViewProxy と befold 側の WebViewDocumentRenderer は今回の境界に含めない（SwiftUI が作った実体を AppKit のメニューへ持ち出す配線で、境界とは方向が逆）。NSViewRepresentable の dismantleNSView がシグネチャに WKWebView を要求するため、アプリ全体から WKWebView は消えない。

**行数に注意（指摘 F7）**: ViewerRenderer の型グループは着手時 351 行（閾値 400）。生成・破棄を畳んで超えるなら閾値を緩めず ViewerRenderer+Surface.swift へ extension 分割する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ViewerRenderer が WKWebView 型を保持も参照もせず、抽象越しに描画面を操作している
- [x] #2 WKWebView の生成・configuration 組み立て・message handler 登録/解除・コンテンツルールリスト適用が、WebKitRenderSurface を唯一の入口とする一群に閉じている（着手時の判断: ViewerWebViewFactory 270 行を WebKitRenderSurface へ物理的に畳むと 4 責務・330 行の型になり、このプロジェクトの型分割の規約と逆方向になるため、型を合体させるのではなく入口を 1 つにする）
- [x] #3 BefoldRenderKit で import WebKit を含むファイル数と、WKWebView という型名に言及するファイル数の両方を計測し、before（15 / 11）からの after を Notes に記録している
- [x] #4 「WKWebView を生成してよいのは WebKit 側の一群だけ」が機械で守られている（swiftlint の custom_rules など、破ると落ちるもの）
- [x] #5 型グループの行数が閾値 400 以内で、swiftlint のベースライン差分がゼロ
- [x] #6 swift test が通り、/webview-smoke と手動の表示確認で回帰が無い（親タスクの AC#5）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（2026-09-08）

### ViewerRenderer から WKWebView を消した
- `makeWebView(...) -> WKWebView` を `makeSurface(...) -> any RenderSurface` へ。
- `dismantle(_ webView: WKWebView)` を `dismantle(_ surface: any RenderSurface)` へ。
- 595.1 で置いた `webView` accessor を撤去。`import WebKit` も落とした。
- **実測: `ViewerRenderer.swift` と `ViewerRenderer+*.swift` の `WKWebView` 言及はコメントのみで、コード上の参照は 0。**

### 構成の入口を 1 つにした
`WebKitRenderSurface.make(options:eventHandler:)` が WKWebView を作る唯一の入口。viewer.html のロードまで済ませて返すので、読み込み忘れの面が配られない。`dismantle(features:)` も同じ型に置いた。

**`ViewerWebViewFactory` を物理的に畳まなかった理由**: 270 行・4 責務（Options / user script 生成 / ハンドラ名一覧 / dismantle）を `WebKitRenderSurface` へ合体させると 330 行の型になり、このプロジェクトの型分割の方針と逆になる。閉じたのは**入口**で、上の層は `WebKitRenderSurface` しか呼ばない。AC#2 はこの判断に合わせて書き換えた。

### 具体型が要る 2 点は残した（親レビュー F3・F4 のとおり）
- `OneShotResult.webView: WKWebView`: QuickLook 拡張がプレビューへ NSView を埋め込むための公開 API。`OneShotRenderer` は `WebKitRenderSurface.make` を直接呼んで具体型を保持し、内部の描画は surface 越しに行う（`as?` の握り潰しを避けた）。
- `ViewerWebView`（NSViewRepresentable）: `makeNSView` が具体的な NSView を返す契約。**WebKit を知っているのはアプリ側のこの 1 点**で、降格に失敗したら `preconditionFailure` で落とす（空の面を配らない）。
- `WebViewProxy` は F3 のとおり対象外。

### 担保（AC#4）
`.swiftlint.yml` に `webview_creation_outside_webkit_layer` を追加。**実測で確認**: 現状 0 件、`ViewerWebView.makeCoordinator` に `WKWebView(frame: .zero)` を足すと error で落ちる（確認後に復元）。本番コードでの WKWebView 生成は `ViewerWebViewFactory.swift:109` の 1 箇所だけ。

### 検証（実測）
- `swift test` **1926 tests / 316 suites すべて pass**
- `/webview-smoke` **PASS**（exit 0）
- `xcodebuild build -scheme befold` **BUILD SUCCEEDED**
- swiftlint ベースライン: main 51 / HEAD 51、真の新規 **0 件**
- 型グループ: `ViewerRenderer` **384 行**（閾値 400）。F7 が予告した増加だが閾値内。extension 分割は合算判定なので数値が減らず（CLAUDE.md の規定）行わない。増分は doc コメントで、削るのは筋が悪い。次に機能を足すときは受け皿を検討すること

### WebKit 依存の最終値（親タスク AC#3）
| 指標 | before | 595.1 | 595.2 | **595.3** |
| --- | --- | --- | --- | --- |
| `import WebKit` を含むファイル | 15 | 13 | 8 | **7** |
| `WKWebView` に言及するファイル | 11 | 9 | 9 | **9**（うち 4 はコメントのみ） |

コード上で WKWebView に触るのは `ViewerWebViewFactory` / `WebKitRenderSurface` / `WebKitSurfaceEventBridge` / `RemoteLoadBlocker` / `OneShotRenderer`（返り値のみ）/ `WebViewProxy`（対象外）の 6 ファイル。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerRenderer から WKWebView 型を消し（コード参照 0、言及はコメントのみを実測）、構成の入口を WebKitRenderSurface.make 1 つに閉じた。ViewerWebViewFactory を物理的に畳まなかったのは 4 責務 330 行の型になり型分割の方針と逆になるためで、AC#2 をその判断に合わせて書き換えてある。具体型が要る 2 点（QuickLook が埋め込む NSView、NSViewRepresentable の契約）はアプリ側に残し、降格失敗を握り潰さない形にした。担保は swiftlint の webview_creation_outside_webkit_layer で、違反を入れると落ちることを実測済み。swift test 1926 件 pass、/webview-smoke PASS、xcodebuild BUILD SUCCEEDED、swiftlint 新規違反 0 件、型グループ 384 行（閾値 400 内）。import WebKit は 15→7 ファイル。
<!-- SECTION:FINAL_SUMMARY:END -->
