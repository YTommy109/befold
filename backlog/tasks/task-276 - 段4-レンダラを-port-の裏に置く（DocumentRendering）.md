---
id: TASK-276
title: '段4: レンダラを port の裏に置く（DocumentRendering）'
status: To Do
assignee: []
created_date: '2026-08-04 00:31'
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
- [ ] #1 レンダラへの命令が protocol 越しになり、コマンド層に WKWebView / JS 文字列が現れない
- [ ] #2 fake renderer を注入したテストで、能力に応じて命令が送られる/送られないことを検証している
- [ ] #3 直接 HTML モードの倍率保存など、既存の振る舞いが変わっていない（既存テストが green）
<!-- AC:END -->
