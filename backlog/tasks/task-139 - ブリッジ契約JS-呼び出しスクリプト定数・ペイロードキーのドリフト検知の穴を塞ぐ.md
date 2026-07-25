---
id: TASK-139
title: ブリッジ契約(JS 呼び出しスクリプト定数・ペイロードキー)のドリフト検知の穴を塞ぐ
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:41'
updated_date: '2026-07-25 06:24'
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
- [x] #1 ViewerBridge のプレーン呼び出しスクリプト定数(_mmd*() 群)が配列/列挙として単一情報源化され、テストがそれを反復して viewer.html/JS 内の存在を照合する(手書きリスト廃止)。findNext/findPrev の欠落が塞がれている
- [x] #2 ペイロードキー(href/newWindow 等)が Swift 側で定数化され JS 側と突合されるか、少なくとも契約テストで検証される
- [x] #3 JS 側でブリッジ関数名/ペイロードキーを改名するとテストが失敗することを確認できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerBridge に PlainFunction(String, CaseIterable) を追加し、引数なし呼び出し(_mmdZoomIn/_mmdZoomOut/_mmdZoomReset/_mmdInitZoom/_mmdScrollTarget/_mmdOpenFind/_mmdFindNextIfOpen/_mmdFindPrevIfOpen)を単一情報源化する。callScript(呼び出し文字列)と definitionToken(JS 定義トークン)を導出プロパティにし、既存の *Script 定数・applyZoomScript・currentScrollPositionScript をそこから組み立てる。
2. ペイロードキーを PayloadKey.ReferenceActivated/ScrollPositionChanged/FindOptionsChanged として定数化し、メッセージ名→キー集合の対応表 payloadKeysByMessageName を ViewerBridge に置く(zoomChanged は裸の数値のため対象外)。
3. ViewerRenderer+MessageHandling の body["href"] 等の生文字列を上記列挙の rawValue へ置換する。
4. テスト: (a) bridgeFunctionsExistInViewerHTML から手書きの _mmd*() 存在チェックを削除し PlainFunction.allCases の反復照合へ置換(findNext/findPrev の欠落が塞がる)。(b) 新規テストで viewer-main.js の _mmdPostMessage(_MSG_X, {...}) 送信サイトを走査し、_MSG 定数値→キー集合を抽出して payloadKeysByMessageName と集合一致を検証(未登録メッセージも失敗させる)。
5. AC#3 の確認: JS 側でブリッジ関数名とペイロードキーを一時的に改名して swift test が赤になることを実測し、notes に記録する。
6. swift build / swift test / SwiftLint を通す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装内容:
- ViewerBridge.PlainFunction(String, CaseIterable) を新設し、引数なし JS 呼び出し 8 件(_mmdZoomIn/_mmdZoomOut/_mmdZoomReset/_mmdInitZoom/_mmdScrollTarget/_mmdOpenFind/_mmdFindNextIfOpen/_mmdFindPrevIfOpen)を単一情報源化。callScript / definitionToken を導出プロパティにし、zoomInScript 等の既存定数・applyZoomScript・currentScrollPositionScript を全てそこから組み立てるようにした。
- ペイロードキーを ViewerBridge.PayloadKey.{ReferenceActivated,ScrollPositionChanged,FindOptionsChanged} として定数化し、メッセージ名→キー集合の表 payloadKeysByMessageName を追加(zoomChanged は裸の数値送信のため対象外)。ViewerRenderer+MessageHandling の body["href"] 等の生文字列を rawValue 参照へ置換。
- テストを役割で分割。ViewerBridgeTests はスクリプト生成の検証のみに絞り、JS/HTML ソースを読む契約テストを新規 ViewerBridgeContractTests へ集約。手書きの _mmd*() 存在チェックは PlainFunction.allCases の反復照合に置換し、欠落していた findNext/findPrev を含めて自動で網羅されるようにした。ペイロードは JS の _mmdPostMessage(_MSG_X, {...}) 送信サイトを正規表現で走査し、_MSG 定数値→キー集合を抽出して Swift 側宣言と集合一致を検証(未宣言メッセージも失敗する)。

ドリフト検知の実測(AC#3):
viewer-main.js を一時改名して swift test --filter ViewerBridge を実行し、2 件が失敗することを確認した。
- function _mmdFindNextIfOpen() → _mmdFindNextIfOpenRenamed(): 'JS 側に function _mmdFindNextIfOpen() の定義がない' で失敗(改名前の手書きリストでは検知できなかったケース)
- payload の href: → hrefRenamed:: Expectation failed: (declared → ["href", "newWindow"]) == (site.payloadKeys → ["hrefRenamed", "newWindow"]) で失敗
改名を git checkout で戻した後は再び全て緑。

検証: swift build 成功 / swift test 640 tests in 90 suites 全緑 / SwiftLint 0 serious(違反総数 64→57。ViewerBridgeTests の type_body_length 超過と 'js' 変数名警告を分割時に解消)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブリッジ契約のうち強度が不均一だった 2 層を単一情報源化した。(1) 引数なし JS 呼び出しを ViewerBridge.PlainFunction 列挙にまとめ、呼び出しスクリプトと JS 定義トークンを導出。契約テストは allCases を反復して viewer.html/viewer-main.js と照合するため、照合リストから漏れていた _mmdFindNextIfOpen/_mmdFindPrevIfOpen も自動で守られる。(2) postMessage ペイロードキーを PayloadKey 列挙 + payloadKeysByMessageName で宣言し、JS の送信サイトを走査して集合一致を検証(未宣言メッセージも失敗)。Swift 側の読み取りも生文字列から列挙参照へ置換した。あわせてテストを『スクリプト生成の検証(ViewerBridgeTests)』と『JS ソースとの突合(ViewerBridgeContractTests)』に分離。検証は JS 側で関数名とペイロードキーを一時改名し該当テストが失敗すること(改名前は緑だった findNext のケースを含む)を実測、復帰後に swift test 640 tests 全緑・SwiftLint 0 serious を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
