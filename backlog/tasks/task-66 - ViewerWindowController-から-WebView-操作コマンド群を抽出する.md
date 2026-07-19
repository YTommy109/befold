---
id: TASK-66
title: ViewerWindowController から WebView 操作コマンド群を抽出する
status: To Do
assignee: []
created_date: '2026-07-19 02:57'
labels: []
dependencies: []
priority: low
type: task
ordinal: 35000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold/App/ViewerWindowController.swift（618 行）にはウィンドウ構築・ファイル切替・参照リンク解決・WebView 操作メニューアクション・NSWindowDelegate の 5 責務が同居している。うちズーム / 印刷 / 検索 / 行番号トグルなどのメニューアクション（:439-514）は webViewProxy しか触らないコマンド群であり、独立したコントローラへ抽出できる。guard let webView = webViewProxy.webView + evaluateJavaScript の 4 回繰り返し（:369, :378, :443, :512）もヘルパーに畳む。TASK-1.5 の減量（ツールバー・スワイプ抽出）の続き。2026-07-19 のアーキテクチャレビューで特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 WebView 操作系メニューアクションが独立した型に抽出されている
- [ ] #2 メニュー・ツールバー・キーボードショートカットの動作が不変
- [ ] #3 既存の ViewerWindowController 系テストが通過する
<!-- AC:END -->
