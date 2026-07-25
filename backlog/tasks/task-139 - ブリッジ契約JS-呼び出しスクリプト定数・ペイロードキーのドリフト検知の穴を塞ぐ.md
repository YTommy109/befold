---
id: TASK-139
title: ブリッジ契約(JS 呼び出しスクリプト定数・ペイロードキー)のドリフト検知の穴を塞ぐ
status: To Do
assignee: []
created_date: '2026-07-24 22:41'
labels:
  - refactor
  - structural
  - js
  - test
dependencies: []
priority: medium
ordinal: 53000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Swift↔JS ブリッジ契約は 3 層あるが強度が不均一。メッセージ名は ViewerBridge の型付き定数を送受両側で共有し安全。しかし (2) プレーン呼び出しスクリプト(_mmdZoomIn() 等の生リテラル)の存在検証は ViewerBridgeTests.bridgeFunctionsExistInViewerHTML の手書き html.contains リストのみで、findNextScript(_mmdFindNextIfOpen())/findPrevScript(_mmdFindPrevIfOpen())が実使用(WebViewCommandController)されているのに照合リストから欠落し、JS 側改名で Cmd+G/Cmd+Shift+G が沈黙して壊れてもテストが緑のまま。(3) ペイロードキー(_mmdPostMessage の href,newWindow 等の生文字列)は Swift 側の body[href] 等と相互照合が皆無でドリフト無防備。TASK-67 は文言キーのみで本件は対象外。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerBridge のプレーン呼び出しスクリプト定数(_mmd*() 群)が配列/列挙として単一情報源化され、テストがそれを反復して viewer.html/JS 内の存在を照合する(手書きリスト廃止)。findNext/findPrev の欠落が塞がれている
- [ ] #2 ペイロードキー(href/newWindow 等)が Swift 側で定数化され JS 側と突合されるか、少なくとも契約テストで検証される
- [ ] #3 JS 側でブリッジ関数名/ペイロードキーを改名するとテストが失敗することを確認できる
<!-- AC:END -->
