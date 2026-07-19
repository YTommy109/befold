---
id: TASK-1.1
title: レンダリングコア（WKWebView ドライバ）を新設 BefoldRenderKit へ抽出する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:38'
updated_date: '2026-07-19 00:53'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/209
parent_task_id: TASK-1
priority: high
ordinal: 100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #209 から移行。ViewerWebView.swift（657行）に固着しているWKWebView構成・viewer.htmlロード・render()評価の組み立て役を BefoldKit に最小コンポーネント（ViewerRenderer）として新設する。find/loadMore/リンク遷移などアプリ専用機能はフック注入構造にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 WKWebView 構成→viewer.html ロード→render 評価を行う WKWebView ドライバ（Coordinator コア）が新設ターゲット BefoldRenderKit に存在する
- [x] #2 アプリ専用機能（find/loadMore/リンク遷移/WebViewProxy/FindOptionsPreference）がフック注入かつオプショナルで、QuickLook から省ける構造になっている
- [x] #3 viewer.html ロードの既定 Bundle が .befoldKitResources（Bundle.main 非依存）になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
【設計判断（2026-07-18 確定）】BefoldKit 直挿しではなく別ターゲット BefoldRenderKit を新設し BefoldKit に依存させる。理由: 抽出対象は import WebKit に加え NSFont/NSWorkspace/NSEvent.ModifierFlags（AppKit）を使い、UI 依存ゼロの純ロジック lib である BefoldKit のテスト容易性を崩すため。BefoldRenderKit はアプリ本体と QuickLook 拡張（.appex）の両方がリンクする。

【抽出単位】SwiftUI の NSViewRepresentable ラッパ（ViewerWebView）ではなく、その内部の WKWebView ドライバ（Coordinator コア）を抽出する。appex は representable ではなく素の WKWebView を QLPreviewingController に載せるため。

1. BefoldRenderKit ターゲットを新設（framework、BefoldKit 依存）。Package.swift / project.yml に BefoldKit と同パターンで1ターゲット追加。
2. WKWebView 構成・userScript 一括注入（ViewerWebView.swift:45-108）・viewer.html ロード（loadViewerHTML :137-141）・render 適用（Coordinator.updateContent :319-411, applyRender :474-509, renderableContent :535-540）・ロード完了待ちキュー（isReady/pendingUpdate）を BefoldRenderKit の WKWebView ドライバへ移す。
3. loadViewerHTML の既定 bundle を .rendering（アプリ本体拡張）から .befoldKitResources（BundleAccessor、Bundle.main 非依存で appex 安全）に付け替える。Bundle.rendering は不要になれば削除。
4. アプリ専用フックはドライバへ注入で渡す: find/findOptions/loadMore/リンク遷移コールバック、WebViewProxy、FindOptionsPreference は必須引数ではなくオプショナル化し、QuickLook では省略（hostFeatures(loadMore:false, spaceScroll:false) と同型の軽量構築経路）。NSViewRepresentable ラッパ（ViewerWebView）はアプリ本体に残し、ドライバへのフック注入で従来機能を再現する。
5. サンドボックス配慮（task-1.9 と連携）: 直接 HTML モードの allowingReadAccessTo（:351）と相対画像埋め込みは appex で権限がないため、ドライバ側でフラグ制御できる注入点を用意する（実挙動の無効化は 1.9 で行う）。
6. 既存テスト（ViewerWebViewCoordinatorTests, DirectHTMLLinkPolicyTests）は app 側に残す静的関数対象なので基本無変更の見込み。swift build / swift test で回帰確認。WKWebView 実描画は /webview-smoke で手動確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-07-19 着手前の現状確認・計画の具体化:
- TASK-1.9 で RendererFeatures(BefoldKit) が既に導入済みで、allowDirectHTML/embedImages/allowsInteractiveBridging によるフック無効化パターンが確立済み。Bundle.rendering は LocalizedBundle.swift で既に Bundle.befoldKitResources のエイリアスになっており、AC#3(既定bundleを.befoldKitResourcesに)は「エイリアスをやめて直接参照に変える」だけで達成できる。
- 現在の ViewerWebView.swift(686行)の行番号は計画確定時(2026-07-18)から変わっていない(TASK-1.7/1.8/1.9/1.10/1.11/1.12はViewer.js/ContentLoader/NormalizedTextCache側の変更でありViewerWebView.swiftへの影響は軽微)。makeNSView:48-115, loadViewerHTML:145-149, updateContent:337-432, applyRender:495-531, renderableContent:566-572, isReady/pendingUpdate:218-219 で計画記載と一致確認済み。

具体化した実装単位(単純化: 新しい抽象を発明せず、BefoldKitに既にあるRendererFeaturesと同じ「Foundation純粋データはBefoldKitへ」パターンを踏襲する):
- 新規ターゲット BefoldRenderKit (framework, BefoldKit依存, WebKit+AppKit import) を作成:
  - WebViewProxy.swift (befold/Viewer/WebViewProxy.swiftから移動。WebKit依存のためBefoldKitには置けない)
  - ViewerRenderer.swift (ViewerWebView.Coordinatorのコア。makeWebView/updateContent/delegateメソッド/loadViewerHTML静的関数/messageHandlerNames静的関数/dismantle/TruncationState/WeakScriptMessageHandler)
  - ViewerRenderer+RenderHelpers.swift (handleLoadMoreLines/applyRender/shouldEnterDirectHTMLMode/isFileOrModeSwitch/recordRendered/renderableContent/reloadViewerHTML)
  - ViewerRenderer+DirectHTMLLinkPolicy.swift (decidePolicyForDirectHTMLAware/DirectHTMLLinkAction/directHTMLLinkPolicy/URL.deletingFragment)
- BefoldKit に追加(Foundation純粋データのため。WebKit/AppKit依存なし):
  - LoadMoreLinesResult.swift (ViewerStore.swiftから移動)
  - FindOptionsPreference.swift (befold/App/FindOptionsPreference.swiftから移動。@MainActorだがUIKit/AppKit依存はなし)
- ViewerWebView.swift はNSViewRepresentableラッパのみに縮小し、ViewerRendererへ委譲する薄い層になる。
- LocalizedBundle.swift の Bundle.rendering は呼び出し元がloadViewerHTMLの1箇所のみのため、移設後は不要になり削除する。
- テスト(ViewerWebViewCoordinatorTests, DirectHTMLLinkPolicyTests)はbefoldTestsに残し、参照をViewerWebView.Coordinator→ViewerRendererに変更、import BefoldRenderKitを追加。

検証結果: swift build 成功、swift test 395件全パス、xcodebuild build -scheme befold 成功(BefoldRenderKit含む全ターゲットリンク確認)、scripts/webview-smoke.swift PASS(CSP下でのスクリプト稼働・mmd/md描画・外部画像/data:iframeブロックに回帰なし、viewer.htmlはBefoldKitのリソースバンドル経由のまま)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWebView.swift(686行)に固着していたWKWebViewドライバ(構成・viewer.htmlロード・render適用・postMessageハンドラ・ロード完了待ちキュー・直接HTMLリンクポリシー)を新設ターゲットBefoldRenderKit(BefoldKit依存)のViewerRendererへ抽出した。find/loadMore/リンク遷移コールバック・WebViewProxy・FindOptionsPreferenceはすべてOptionalなフック注入になり、QuickLook等の静的1回描画ホストでは省略できる。LoadMoreLinesResult/FindOptionsPreferenceはFoundation純粋データのためBefoldKitへ、WebKit依存のWebViewProxyはBefoldRenderKitへ移設。loadViewerHTMLの既定bundleはアプリ専用のBundle.renderingエイリアス(削除済み)ではなくBundle.befoldKitResourcesを直接参照する。ViewerWebView.swiftはNSViewRepresentableのブリッジ層のみに縮小。Package.swift/project.ymlにBefoldRenderKitターゲットを追加しxcodegen generateで反映。swift build/swift test(395件)/xcodebuild build/webview-smokeで回帰なしを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
