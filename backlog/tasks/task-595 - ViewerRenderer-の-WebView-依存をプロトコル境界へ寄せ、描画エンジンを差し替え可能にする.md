---
id: TASK-595
title: ViewerRenderer の WebView 依存をプロトコル境界へ寄せ、描画エンジンを差し替え可能にする
status: In Progress
assignee:
  - '@claude'
created_date: '2026-09-07 15:00'
updated_date: '2026-09-08 13:22'
labels: []
dependencies:
  - TASK-594
ordinal: 866000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldRenderKit は 19 ファイル 1,952 行のうち 16 ファイルが WebKit / AppKit を直接 import しており、WKWebView が層の全域に露出している（ViewerScriptDispatcher・WebViewProxy・PageZoomProjector・RemoteLoadBlocker・DirectHTMLModeController など）。一方で描画の実体は Swift 側ではなく BefoldKit/Resources の viewer.html + viewer-bundle.js + mermaid.min.js にあり、Swift 側の責務は「HTML をロードし、evaluateJavaScript でコマンドを送り、ブリッジで結果を受ける」ことに尽きる。

つまり WKWebView は本来 1 つの実装詳細だが、現状は境界が無いため層全体がそれに固着している。境界を引くと次の 2 つが得られる。

1. 描画エンジンの差し替えが可能になる（将来 Windows 版を検討する場合、置き換えるのは WebView2 ドライバだけで済み、Web 資産と描画ロジックはそのまま使える）
2. 現状でもテスト可能性が上がる。今は WKWebView 実体なしに ViewerScriptDispatcher / RenderedStateMirror の経路を組めない

Windows 版を作ると決めなくても着手できる範囲であり、決めてからでは手戻りが大きい。なお境界の設計は「WKWebView を薄く包む」ことではなく、この層が実際に必要としている操作（ロード / スクリプト実行 / ナビゲーション判断 / ズーム / メッセージ受信）を洗い出して最小の口にすること。既存の WebViewProxy は AppKit のメニューアクションへの橋渡し用の弱参照ホルダーであって、この境界そのものではない点に注意。

大きい変更のため、着手前に /review-design を回すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerRenderer が WKWebView 型に直接依存せず、抽象（プロトコル）越しに描画面を操作している
- [ ] #2 抽象が提供する操作の一覧と、それぞれが必要な理由が doc コメントで示されている（WKWebView の API をそのまま写したものではない）
- [ ] #3 WKWebView 実装が 1 つの型に閉じており、BefoldRenderKit で WebKit を import するファイル数が現状の 16 から有意に減っている（着手時に実測して before/after を Notes に記録する）
- [ ] #4 抽象のテスト用実装（fake）を使い、WKWebView 実体なしに描画コマンドの送出経路を検証するテストが 1 つ以上ある
- [ ] #5 既存の描画まわりのテストが通り、/webview-smoke と手動の表示確認で回帰が無いことを確認している
- [ ] #6 着手前に /review-design を回し、結果を Implementation Plan に反映している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 設計の骨子（探索の実測にもとづく）

Kit 内で WKWebView に**実際に触るのは 8 ファイル**（ViewerWebViewFactory / ViewerScriptDispatcher / DirectHTMLModeController / ReferenceResolutionQueue / PageZoomProjector / RemoteLoadBlocker / ViewerRenderer+RenderHelpers / OneShotRenderer）。残り 12 は既に独立している。うち 3 ファイル（RenderValues / RenderedStateMirror / ViewerRenderer+ContentUpdate）は `import WebKit` があるだけで WebKit 型を使っていない（ContentUpdate は引数の型名としてのみ通す）。

必要な操作は次の 7 つに収まる。**WKWebView の API を写したものではなく、この層が実際に使っている操作だけ**（実測で列挙）。

| 操作 | なぜ要るか | 現在の箇所 |
| --- | --- | --- |
| `evaluateScript(_:completion:)` | 描画コマンドの送出。Kit 内 5 箇所すべてが**返り値を使っていない**ので、返すのはエラーのみ | ViewerScriptDispatcher / PageZoomProjector / ReferenceResolutionQueue / RenderHelpers / OneShotRenderer |
| `callScript(_:) async throws -> Any?` | 初回描画の完了を待つ唯一の経路（`callAsyncJavaScript`）。Kit 内で await が要るのはここだけ | OneShotRenderer |
| `loadLocalFile(_:allowingReadAccessTo:)` | viewer.html のロードと直接 HTML モード | ViewerWebViewFactory / DirectHTMLModeController |
| `loadHTML(_:mimeType:encoding:baseURL:)` | charset 宣言の無い HTML を UTF-8 明示でロード | DirectHTMLModeController |
| `zoom` (get/set) | 直接 HTML モードの前後で倍率を維持 | DirectHTMLModeController |
| `currentURL` (get) | リンククリックの同一文書判定 | DirectHTMLModeController |
| `isContentJavaScriptEnabled` (set) | 直接 HTML モードで JS を切り、戻すときに入れ直す | DirectHTMLModeController / RenderHelpers |

これ以外（configuration・userContentController・contentRuleList・navigationDelegate・allowsMagnification・drawsBackground・WKWebView の生成）は**構成と破棄の関心**なので、プロトコルに出さず実装型の内側へ閉じる。

## 分割の必要性（要ユーザー判断）

境界は 2 方向ある。

- **送出（Kit → 描画面）**: 上の 7 操作。プロトコルで切れる
- **受信（描画面 → Kit）**: `WKNavigationDelegate` の 4 メソッド（ViewerNavigationCoordinator）と `WKScriptMessageHandler`（BridgeMessageRouter）。`decidePolicyFor` は**戻り値を返す**ので単なるイベントではない

AC#1（ViewerRenderer が WKWebView 型に依存しない）は送出だけでは達成できない。ViewerRenderer は `webView: WKWebView?` を保持し（ViewerRenderer.swift:49）、`webView.navigationDelegate` を書いている（同 :165）ため、受信側と生成側も畳む必要がある。合計で 12 ファイル・800 行規模になる見込み。

サブタスクへの分割案（着手前にユーザーへ提示する）:
1. 送出方向の境界（プロトコル + WKWebView 実装 + fake + AC#4 のテスト）
2. 受信方向（ナビゲーション事象・ブリッジメッセージを Kit 側の口へ寄せ、WebKit 準拠を実装型へ閉じる）
3. 生成・破棄（ViewerWebViewFactory / RemoteLoadBlocker を実装型へ畳み、ViewerRenderer から WKWebView 型を消す）

## 着手前に済ませたこと
- AC#3 の before 実測（Notes に記録）
- `/webview-smoke` が 2026-08-30 から FAIL していた件を修復（コミット 1a9289cc）。AC#5 のベースラインが緑になった

--- /review-design の結果（2026-09-08。AC#6）---
F1. [項目2・8] **`evaluateScript` を async にしない。** ViewerScriptDispatcher.applyRender は await の後 :117〜:139 を await 無しの一続きに保っており（コメントに理由あり）、これは TASK-320 / 334 / 336 で 3 連鎖した「描画ミラーの確定漏れ」を構造で塞いだ結果。境界を async にすると同型の 4 件目を招く。送出は同期・fire-and-forget、返すのはエラーのみ（Kit 内 5 箇所すべてが返り値を使っていない実測がこれを許す）。
F2. [項目2] `decidePolicyFor` の completion handler 版は意図的な選択（ViewerNavigationCoordinator.swift:18-20 に「async 版だとサスペンド中に renderer が消える窓が生まれる」と明記）。受信方向を抽象化する際に async にしない。
F3. [項目3] **Kit の外にも WKWebView 直接操作が 6 箇所ある。** `WebViewProxy.webView` は public weak var で、befold の WebViewDocumentRenderer が evaluateJavaScript / pageZoom R/W / printOperation を直に叩く（:54, :93, :107, :134）。しかも :108 は Kit 内に 1 つも無い「返り値を使う evaluateJavaScript」。printOperation は WKWebView そのものを要求するため、プロトコルに含めるか WebViewProxy を対象外と明言するかを決める必要がある → **今回は対象外と明言する**（AC#1 は ViewerRenderer が対象。WebViewProxy は SwiftUI が作った実体を AppKit のメニューへ持ち出す配線ケーブルであり、境界とは方向が逆）。
F4. [項目5] **SwiftUI 側が WKWebView 型を要求する。** befold/Viewer/ViewerWebView.swift は NSViewRepresentable で `dismantleNSView(_ nsView: WKWebView, coordinator: ViewerRenderer)` のように具体型がシグネチャに出る。境界を入れても WKWebView はアプリから消えない。AC の解釈を「Kit を非依存にする」に確定する（「アプリ全体から消す」ではない）。
F5. [項目7] **AC#3 の指標が緩い。** 「import WebKit のファイル数」は未使用 import を消すだけで 15→12 に見せられる（実測: RenderValues / RenderedStateMirror / ViewerRenderer+ContentUpdate の 3 つは import があるだけで WebKit 型を使っていない）。**併せて「WKWebView という型名に言及するファイル数」を測る — 現在 11**。こちらが実際の固着度。
F6. [項目9] 「WKWebView 実装は 1 つの型に閉じる」を doc コメントで守れない。swiftlint の custom_rules を使う（TASK-598 の pdf_document_creation_outside_probe と同型。included を BefoldRenderKit、excluded を実装型 1 ファイルに）。
F7. [項目10] 型グループ実測: ViewerRenderer **351 行**（閾値 400・余裕 49 行）/ OneShotRenderer 214 / ViewerWebViewFactory 182 / DirectHTMLModeController 177 / ViewerScriptDispatcher 169。ViewerRenderer が最も危うく、595.3 で生成・破棄を畳むときに超える恐れがある。超えるなら閾値を緩めず `ViewerRenderer+Surface.swift` へ extension 分割する。

## 分割の決定（ユーザー確認済み・2026-09-08）
3 サブタスク（595.1 送出方向 / 595.2 受信方向 / 595.3 生成・破棄）に分ける。CLAUDE.md の規定によりサブタスクごとに /review-design を回す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## AC#3 の before 実測（2026-09-08・着手時）

`BefoldApp/BefoldRenderKit/*.swift` を対象に計測。

| 指標 | 値 |
| --- | --- |
| .swift ファイル数 | 20 |
| **`import WebKit` を含むファイル数** | **15** |
| `import AppKit` を含むファイル数 | 4 |
| WebKit または AppKit | 17 |
| 総行数 | 1977 |

起票時の Description は「19 ファイル 1,952 行のうち 16 ファイル」と書いているが、これは TASK-594 で `OpenDisposition+NSEvent.swift`（22 行・AppKit）を足す前の値。**AC#3 の追跡対象は WebKit の 15 ファイル**とする（AppKit は別の関心で、`OpenDisposition+NSEvent` と `DirectHTMLLinkPolicy` は修飾キー解釈という WKWebView と無関係な理由で AppKit を使っている）。

ファイル別の内訳:

| ファイル | import | 行数 |
| --- | --- | --- |
| BridgeMessageRouter.swift | WebKit | 93 |
| ContentUpdatePlanner.swift | - | 144 |
| DirectHTMLLinkPolicy.swift | AppKit | 57 |
| DirectHTMLModeController.swift | AppKit+WebKit | 177 |
| OneShotRenderer.swift | WebKit | 214 |
| OpenDisposition+NSEvent.swift | AppKit | 22 |
| PageZoomProjector.swift | WebKit | 62 |
| ReferenceResolutionQueue.swift | WebKit | 86 |
| RemoteLoadBlocker.swift | WebKit | 88 |
| RenderValues.swift | WebKit | 86 |
| RenderableContent.swift | - | 17 |
| RenderedStateMirror.swift | WebKit | 68 |
| ViewerNavigationCoordinator.swift | WebKit | 78 |
| ViewerReadinessGate.swift | - | 47 |
| ViewerRenderer+ContentUpdate.swift | WebKit | 99 |
| ViewerRenderer+RenderHelpers.swift | WebKit | 72 |
| ViewerRenderer.swift | WebKit | 180 |
| ViewerScriptDispatcher.swift | WebKit | 169 |
| ViewerWebViewFactory.swift | AppKit+WebKit | 182 |
| WebViewProxy.swift | WebKit | 36 |

## 着手時に見つかった既存の破損: /webview-smoke が 2026-08-30 から落ちている

AC#5 が `/webview-smoke` の通過を求めているため着手前にベースラインを取ったところ、**変更前の時点で 1 件落ちていた**。

```
pdf iframe src scheme: Optional(noframe)
FAIL: PDF iframe が blob: URL で生成されなかった
exit=1
```

原因は TASK-595 と無関係な**スモークテスト側の陳腐化**。実測:

- `scripts/webview-smoke.swift:296-305` が `#diagram-wrap iframe` の src が `blob:` で始まることを検証している
- PR #610（`71def7e7`・2026-08-30「PDF の表示を PDFKit へ移し、連続スクロールと縦フィットにする」）が、コミット本文のとおり「viewer 側の PDF 専用コードと CSP の frame-src blob: を撤去」した
- `git grep -c createObjectURL 71def7e7^ -- BefoldApp/viewer-src` → `renderers.ts:1`、`71def7e7` → **0 件**。blob iframe の生成は #610 で消えている
- `scripts/webview-smoke.swift` の最終変更は `df5a0122`（2026-08-24）で **#610 より前**。追随していない

つまり PDF は WKWebView で描かなくなったのに、スモークテストだけが iframe の存在を要求し続けている。守るべき対象が既に無い検証なので、判定を緩めるのではなく**検証項目ごと削除する**のが正しい（TASK-595 の実装前に片付ける）。
<!-- SECTION:NOTES:END -->
