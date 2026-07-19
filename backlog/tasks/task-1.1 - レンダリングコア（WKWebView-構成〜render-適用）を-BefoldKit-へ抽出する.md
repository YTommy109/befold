---
id: TASK-1.1
title: レンダリングコア（WKWebView ドライバ）を新設 BefoldRenderKit へ抽出する
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 13:42'
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
- [ ] #1 WKWebView 構成→viewer.html ロード→render 評価を行う WKWebView ドライバ（Coordinator コア）が新設ターゲット BefoldRenderKit に存在する
- [ ] #2 アプリ専用機能（find/loadMore/リンク遷移/WebViewProxy/FindOptionsPreference）がフック注入かつオプショナルで、QuickLook から省ける構造になっている
- [ ] #3 viewer.html ロードの既定 Bundle が .befoldKitResources（Bundle.main 非依存）になっている
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
