---
id: TASK-595.2
title: 描画面からの受信を Kit 側の口へ寄せる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-08 13:23'
updated_date: '2026-09-08 13:51'
labels: []
dependencies:
  - TASK-595.1
parent_task_id: TASK-595
ordinal: 869000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-595 の 2/3（受信方向）。

WKWebView から Kit へ上がってくる事象を、WebKit の型に依存しない口で受ける。現状の準拠は 2 つ。

- ViewerNavigationCoordinator（WKNavigationDelegate）: 実装しているのは 4 メソッドだけ — didFinish / didFailProvisionalNavigation / didFail / decidePolicyFor
- BridgeMessageRouter（WKScriptMessageHandler）: userContentController(_:didReceive:) の 1 つだけ。message.name と message.body しか読まない

**decidePolicyFor を async にしないこと（親タスクの /review-design 指摘 F2）。** ViewerNavigationCoordinator.swift:18-20 が completion handler 版を選んだ理由を明記している（async 版だとサスペンド中に renderer が消える窓が生まれる）。この判断を壊さない形で抽象化する。

decidePolicyFor は戻り値を返すため、単なる一方向イベントではない点に注意。WKNavigationAction から実際に読んでいるのは navigationType / request.url / modifierFlags の 3 つだけで、返すのは .allow / .cancel の 2 値だけ（実測）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ナビゲーション事象とブリッジメッセージを受ける口が WebKit の型を含まない形で定義され、それぞれ「何を伝えるためのものか」が doc コメントで示されている
- [x] #2 リンククリックの可否判断が完了ハンドラ方式のまま（async 化していない）で、その理由が doc コメントに残っている
- [x] #3 WKNavigationDelegate / WKScriptMessageHandler への準拠が、595.1 で作った WKWebView 実装型の側に閉じている
- [x] #4 fake から受信事象を流し込み、WKWebView 実体なしに Kit 側の反応（readiness 遷移・ブリッジ分岐）を検証するテストがある
- [x] #5 swift test が通り、/webview-smoke が PASS する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装と検証（2026-09-08）

### 追加
- `SurfaceEvents.swift`: WebKit を含まない受け口 2 つ（`SurfaceNavigationObserver` / `SurfaceBridgeMessageObserver`）と値型（`SurfaceNavigationRequest` / `SurfaceNavigationDecision`）。
- `WebKitSurfaceEventBridge.swift`: WebKit のデリゲート準拠を引き受け、翻訳だけを行う唯一の場所。

### WebKit 準拠が外れた型
- `ViewerNavigationCoordinator`: `NSObject, WKNavigationDelegate` → `SurfaceNavigationObserver`。`import WebKit` を落とした。
- `BridgeMessageRouter`: `NSObject, WKScriptMessageHandler` → `SurfaceBridgeMessageObserver`。同上。
- `DirectHTMLModeController.decidePolicy` が `WKNavigationAction` / `WKNavigationActionPolicy` を受け渡さなくなり、`import WebKit` を落とした。

### 翻訳で列挙を潰しかけた（自分で入れて自分で気づいた）
最初 `navigationType == .linkActivated ? .linkActivated : .other` と 2 値へ写したが、**元の判定は 3 分岐**（`.other` → allow / `.linkActivated` → 分類 / **それ以外は cancel**）で、2 値にするとリロード・戻る/進む・フォーム送信が黙って allow に化ける。`Kind` を `.linkActivated` / `.programmatic` / `.otherInteraction` の 3 つにし、「2 値へ潰さないこと」と理由を doc に書いた。

### テストから WebKit 実体が消えた
受け口が name/body と値型になったので、テスト側のスキャフォールドが不要になった。
- `ViewerRendererMessageStubs.ScriptMessage`（`WKScriptMessage` サブクラス）と `.WebView`（`WKWebView` サブクラス）を**削除**（計 40 行）。
- `ViewerRendererAppendTruncationTests` / `ViewerRendererResolveReferencesTests` が fake（`Stubs.Surface`）で動くようになり、両ファイルから `WK` の文字が 0 になった。
- `ViewerNavigationCoordinatorLifetimeTests` は `WKWebView` も `WKNavigationAction` も作らなくなった。

### 未使用の import を落とした
`RenderedStateMirror` / `RenderValues` / `ViewerRenderer+ContentUpdate` は `import WebKit` があるだけで WebKit 型を 1 つも使っていなかった（`grep -c 'WK[A-Z]'` で 0 を確認してから削除）。親レビューの F5 が「これだけで数を減らすと見せかけになる」と指摘した分で、実際の脱依存を済ませた後に落としている。

### 検証（実測）
- `swift test` **1926 tests / 316 suites すべて pass**
- `/webview-smoke` **PASS**（exit 0）
- `xcodebuild build -scheme befold` **BUILD SUCCEEDED**
- swiftlint ベースライン: main 51 / HEAD 51、真の新規 **0 件**

### WebKit 依存の推移
| 指標 | before | 595.1 後 | 595.2 後 |
| --- | --- | --- | --- |
| `import WebKit` を含むファイル | 15 | 13 | **8** |
| `WKWebView` に言及するファイル | 11 | 9 | **9** |

残る 8 ファイルは OneShotRenderer / RemoteLoadBlocker / ViewerRenderer+RenderHelpers / WebKitRenderSurface / WebViewProxy / ViewerWebViewFactory / ViewerRenderer / WebKitSurfaceEventBridge。うち生成・破棄まわり（RemoteLoadBlocker / ViewerWebViewFactory / ViewerRenderer / RenderHelpers）が 595.3 の対象。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
描画面からの受信を WebKit 非依存の 2 つの口（SurfaceNavigationObserver / SurfaceBridgeMessageObserver）へ寄せ、WKNavigationDelegate と WKScriptMessageHandler の準拠を WebKitSurfaceEventBridge 1 型へ閉じた。可否判断は同期のまま（async 化するとサスペンド中に renderer が消える窓が生まれるという既存の設計判断を壊さない）。翻訳時に遷移種別を 2 値へ潰しかけたが、元が 3 分岐でリロードや戻るが allow に化けると気づき、3 値の列挙にして理由を doc に残した。受け口が値型になったことでテストから WKWebView / WKScriptMessage のサブクラス（40 行）が不要になり削除。swift test 1926 件 pass、/webview-smoke PASS、xcodebuild BUILD SUCCEEDED、swiftlint 新規違反 0 件。import WebKit は 13→8 ファイル。
<!-- SECTION:FINAL_SUMMARY:END -->
