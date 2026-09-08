---
id: TASK-595.3
title: 描画面の生成と破棄を実装型へ畳み、ViewerRenderer から WKWebView 型を消す
status: To Do
assignee: []
created_date: '2026-09-08 13:23'
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
- [ ] #1 ViewerRenderer が WKWebView 型を保持も参照もせず、抽象越しに描画面を操作している
- [ ] #2 WKWebView の生成・configuration 組み立て・message handler 登録/解除・コンテンツルールリスト適用が 1 つの実装型の内側に閉じている
- [ ] #3 BefoldRenderKit で import WebKit を含むファイル数と、WKWebView という型名に言及するファイル数の両方を計測し、before（15 / 11）からの after を Notes に記録している
- [ ] #4 「WKWebView 実装は 1 つの型に閉じる」が機械で守られている（swiftlint の custom_rules など、破ると落ちるもの）
- [ ] #5 型グループの行数が閾値 400 以内で、swiftlint のベースライン差分がゼロ
- [ ] #6 swift test が通り、/webview-smoke と手動の表示確認で回帰が無い（親タスクの AC#5）
<!-- AC:END -->
