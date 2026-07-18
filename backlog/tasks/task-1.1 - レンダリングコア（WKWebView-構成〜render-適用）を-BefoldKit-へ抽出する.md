---
id: TASK-1.1
title: レンダリングコア（WKWebView 構成〜render 適用）を BefoldKit へ抽出する
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 10:47'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/209
parent_task_id: TASK-1
priority: medium
ordinal: 6100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #209 から移行。ViewerWebView.swift（657行）に固着しているWKWebView構成・viewer.htmlロード・render()評価の組み立て役を BefoldKit に最小コンポーネント（ViewerRenderer）として新設する。find/loadMore/リンク遷移などアプリ専用機能はフック注入構造にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 WKWebView構成→viewer.htmlロード→renderScript評価だけを行う最小コンポーネントが BefoldKit に存在する
- [ ] #2 アプリ専用機能（find/loadMore/リンク遷移等）がフック注入で追加される構造になっている
- [ ] #3 Bundle.rendering が BefoldKit に移設されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldKit に ViewerRenderer を新設し、WKWebViewConfiguration 構築(46-58,105-119行相当)・Bundle.rendering からの viewer.html ロード(loadViewerHTML相当)・render()評価(ViewerBridge.renderScript の evaluateJavaScript、514-524行相当)のみを最小責務として実装する。find/findOptions/bannerStrings 等アプリ固有スクリプトや追加メッセージハンドラは、初期化時に外部から渡す [WKUserScript] 配列・ハンドラ辞書としてフック注入できる構造にする。ロード完了待ち(isReady/pendingUpdate)キューも汎用部分としてここに含める。
2. Bundle.rendering を BefoldApp/befold/App/LocalizedBundle.swift から BefoldKit/BundleAccessor.swift に移設する(l10n は app 側に残す)。
3. ViewerWebView.swift の makeNSView/loadViewerHTML/applyRender の該当部分を ViewerRenderer 経由に置き換える。direct HTMLモード・リンク遷移ポリシー(directHTMLLinkPolicy)・find/loadMore の具体的コールバック実装は BefoldKit に移さず app 側に残し、ViewerRenderer へのフックとして注入する。
4. 既存テスト(ViewerWebViewCoordinatorTests, DirectHTMLLinkPolicyTests)は対象の静的関数が app 側に残るため変更不要と見込む。swift build / swift test で回帰確認する。
5. WKWebView 実体を伴う GUI 層(makeNSView/updateNSView の実描画)は規約通り自動テスト対象外のため、/webview-smoke で手動スモーク確認する。
6. アーキテクチャ上の注意点: BefoldKit は現状 WebKit 非依存の「純粋ロジックライブラリ」だが、本タスクで初めて WebKit(WKWebView)への依存を持ち込むことになる(macOS system framework のため追加のリンク設定は不要)。AC#1 が明示的に要求しているため方針として妥当と判断するが、実装前にユーザーへ確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ユーザー判断により保留。BefoldKit への WebKit 依存持ち込み方針(直接追加 vs 別ターゲット分離)について設計判断中、着手を後回しにすることに決定。次回再開時はこのアーキテクチャ判断の結論を得てから実装に入る。
<!-- SECTION:NOTES:END -->
