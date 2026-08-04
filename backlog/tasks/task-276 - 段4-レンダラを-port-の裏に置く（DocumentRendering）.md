---
id: TASK-276
title: '段4: レンダラを port の裏に置く（DocumentRendering）'
status: Done
assignee: []
created_date: '2026-08-04 00:31'
updated_date: '2026-08-04 00:38'
labels:
  - architecture
dependencies: []
priority: high
ordinal: 466000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0002 の段 4。

WebViewCommandController が WKWebView と ViewerBridge の JS 文字列を直接扱っているため、レンダラへの命令を検証できる境界が無い。ウィンドウ系テストは makeContentView: placeholderViewerContent を注入して webViewProxy.webView が常に nil になるので、evaluate の `guard let webView else { return }` により **JS 契約のズレも呼び出し順の変更も「no-op が正常」として通過する**。

DocumentRendering プロトコルを境界にし、WKWebView 実装をその adapter にする。コマンド層は「能力の確認 → port へ意図を伝える」だけにし、JS の詳細は adapter に閉じる。これによりテストは fake renderer で「何が命じられたか」を検証できるようになる。

TASK-273（判定・変換のコスト削減）とは別物だが、ADR では段 4 に TASK-273 の一部（テストの空白）が対応づけられている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 レンダラへの命令が protocol 越しになり、コマンド層に WKWebView / JS 文字列が現れない
- [x] #2 fake renderer を注入したテストで、能力に応じて命令が送られる/送られないことを検証している
- [x] #3 直接 HTML モードの倍率保存など、既存の振る舞いが変わっていない（既存テストが green）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-04・ADR 0002 段 4）

- **port**: befold/Viewer/DocumentRendering.swift。applyZoom / applyCodeFont / changeZoom / openFind / findNext / findPrevious / printDocument / currentScrollPosition / isDirectHTMLMode。
- **adapter**: befold/App/WebViewDocumentRenderer.swift。WebViewProxy 経由の生存確認、ViewerBridge の JS 文字列、直接 HTML モードの pageZoom 計算をここに閉じた。
- **コマンド層**: WebViewCommandController から WKWebView / WebKit / ViewerBridge の JS が消え、import も AppKit + BefoldKit だけになった。責務は「能力の確認 → port へ意図を伝える → 結果の保存先を決める」。倍率の保存は、直接 HTML モードで adapter が返した値のときだけ行う（通常モードは JS からの通知経由なので nil が返る）。

## テストの空白が埋まった
従来はウィンドウ系テストが placeholderViewerContent を注入するため webViewProxy.webView が常に nil で、evaluate の guard により **JS 契約のズレも呼び出し順の変更も「no-op が正常」として通過**していた。fake renderer で「何が命じられたか」を受け取れるようになり、次を固定した。

- 能力が無ければユーザー操作はレンダラへ届かない
- 能力があれば対応する命令が順に届く
- 設定の反映（applyStoredZoom / applyCodeFont）は能力で止めない
- 直接 HTML モードで返った倍率だけを保存する
- スクロール位置は取得できた場合だけ保存する

## 確認済み
- swift test 1034 tests / 155 suites green
- swiftlint 新規警告なし（既存 3 件の行数カウントのみ）
- GUI: 倍率 1.75 のファイルを開き直して ⌘- で 1.5 になる（実 WKWebView 経由の経路が生きている）
- docs/dev/native-app-design.md の Viewer/ コンポーネント表に PreviewTarget / ViewerCapabilities / DocumentRendering を追記
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
DocumentRendering を境界にし、WKWebView と JS 文字列を WebViewDocumentRenderer へ閉じた。コマンド層は能力の確認と保存先の決定だけになり、fake renderer で命令の有無を検証できるようになった（従来は WebView 不在で全経路が no-op として通過していた）。swift test 1034 green / swiftlint 新規警告なし / 実 WKWebView での倍率操作も GUI で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
