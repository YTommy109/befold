---
id: TASK-595
title: ViewerRenderer の WebView 依存をプロトコル境界へ寄せ、描画エンジンを差し替え可能にする
status: To Do
assignee: []
created_date: '2026-09-07 15:00'
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
