---
id: TASK-66
title: ViewerWindowController から WebView 操作コマンド群を抽出する
status: Done
assignee: []
created_date: '2026-07-19 02:57'
updated_date: '2026-07-19 04:53'
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
- [x] #1 WebView 操作系メニューアクションが独立した型に抽出されている
- [x] #2 メニュー・ツールバー・キーボードショートカットの動作が不変
- [x] #3 既存の ViewerWindowController 系テストが通過する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 新型 WebViewCommandController(befold/App/) を追加。webViewProxy / perFileState / currentURL クロージャを保持し、WebView 操作コマンド(zoomIn/Out/reset, print, openFind/findNext/findPrevious, applyStoredZoom, saveCurrentScrollPosition)の実ロジックと、guard let webView + evaluateJavaScript の反復を畳む evaluate ヘルパーを持つ。isDirectHTMLMode を validateMenuItem 用に公開。
2. ViewerWindowController 側は @objc メニューアクション(zoomIn/zoomOut/resetZoom/printDocument/find/findNext/findPrevious)を薄い転送メソッドに変更(MainMenuBuilder が #selector で参照するため selector 自体は ViewerWindowController に残す)。performZoom/runFindScript/applyStoredZoomToWebView/saveCurrentScrollPosition の実装本体を新型へ移譲。
3. 単純化検討: 素朴な private ヘルパー関数化だけでは AC#1『独立した型に抽出』を満たさないため、独立型を作る。ただし evaluate ヘルパーで反復畳み込みは達成。
4. WebViewCommandController のロジックをユニットテスト(zoom の directHTML 経路が perFileState.zoom を更新すること等、WebViewProxy に webView nil でもクラッシュしないこと)。GUI 結線(@objc 転送)は薄く保つ。
5. swift build && swift test(既存428件維持)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: befold/App/WebViewCommandController.swift(131行, 新型)を追加し、ズーム(zoomIn/Out/reset)・印刷・検索(openFind/findNext/findPrevious)・applyStoredZoom・saveCurrentScrollPosition の実処理を移譲。guard let webView + evaluateJavaScript の反復は private evaluate ヘルパーに畳んだ。ViewerWindowController の @objc メニューアクションは webViewCommands への薄い転送に変更(MainMenuBuilder が #selector で参照するため selector 自体は残置)。validateMenuItem は webViewCommands.isDirectHTMLMode 経由に。ViewerWindowController は 618→568行。テスト: befoldTests/WebViewCommandControllerTests.swift を追加(isDirectHTMLMode 委譲・webView 未接続時の no-op 安全性)。swift build 成功、swift test 430件全通過(既存428+新規2)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController から WebView 操作コマンド群を新型 WebViewCommandController(befold/App/, 131行) へ抽出。ズーム/印刷/検索/applyStoredZoom/saveCurrentScrollPosition の実処理を移譲し、guard let webView + evaluateJavaScript の反復を evaluate ヘルパーへ集約。@objc メニューアクションは薄い転送のみ残し(MainMenuBuilder の #selector 参照維持のため selector は残置)、ViewerWindowController は 618→568行に減量。検証: swift build 成功、swift test 430件全通過(ViewerWindowController 系 3 スイート含む既存428件 + 新規 WebViewCommandControllerTests 2件)、MainMenuBuilderTests でメニュー selector 結線・ツールバーテストで動作不変を確認。ロジックは verbatim 移設のためメニュー/ツールバー/ショートカット動作は不変。
<!-- SECTION:FINAL_SUMMARY:END -->
