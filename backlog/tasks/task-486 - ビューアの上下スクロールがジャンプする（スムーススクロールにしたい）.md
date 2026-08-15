---
id: TASK-486
title: ビューアの上下スクロールがジャンプする（スムーススクロールにしたい）
status: To Do
assignee: []
created_date: '2026-08-15 11:37'
labels:
  - bug
dependencies: []
priority: medium
type: bug
ordinal: 715500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ユーザー報告: ビューアで上下スクロールすると表示位置がジャンプし、スムーススクロールにならない。位置が飛ぶと読んでいた行を見失うため、滑らかにスクロールしてほしい。

要調査（起票時点では未特定）:

- どの操作で発生するか（キーボードのスクロール操作 / スクロールバー / トラックパッド等）
- どの表示モードで発生するか（Markdown レンダリング / ソース表示 / 差分表示 等）
- WKWebView 側のスクロール実装（viewer.html / CSS の scroll-behavior か、evaluateJavaScript による scrollTo か）のどこでジャンプが起きているか

着手時にまず再現条件をユーザーに確認するか実機で特定し、原因箇所を特定してから修正方針を決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 上下スクロール操作で表示位置が瞬間移動せず、滑らかにスクロールする
- [ ] #2 再現条件（操作・表示モード）が Implementation Notes に記録されている
- [ ] #3 スクロール以外の表示位置制御（検索ヒットへのジャンプ、ファイル再読込時の位置復元など）の挙動が変わっていない
<!-- AC:END -->
