---
id: TASK-595.2
title: 描画面からの受信を Kit 側の口へ寄せる
status: To Do
assignee: []
created_date: '2026-09-08 13:23'
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
- [ ] #1 ナビゲーション事象とブリッジメッセージを受ける口が WebKit の型を含まない形で定義され、それぞれ「何を伝えるためのものか」が doc コメントで示されている
- [ ] #2 リンククリックの可否判断が完了ハンドラ方式のまま（async 化していない）で、その理由が doc コメントに残っている
- [ ] #3 WKNavigationDelegate / WKScriptMessageHandler への準拠が、595.1 で作った WKWebView 実装型の側に閉じている
- [ ] #4 fake から受信事象を流し込み、WKWebView 実体なしに Kit 側の反応（readiness 遷移・ブリッジ分岐）を検証するテストがある
- [ ] #5 swift test が通り、/webview-smoke が PASS する
<!-- AC:END -->
