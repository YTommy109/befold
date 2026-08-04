---
id: TASK-1.3
title: viewer.html のブリッジ postMessage をガード付きヘルパーに一本化し、ホスト機能フラグを導入する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:38'
updated_date: '2026-07-18 11:11'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/211
parent_task_id: TASK-1
priority: medium
ordinal: 6300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #211 から移行。referenceActivated の postMessage だけ存在ガードがなく、ハンドラ未登録の WebView で TypeError になる。5箇所の postMessage を一本化するヘルパーを導入し、Swift 注入のホスト機能フラグで Load More ボタン表示可否・Space キー処理を制御する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 postMessage が一箇所のヘルパー経由で呼ばれている
- [x] #2 referenceActivated のガード未設定が解消されている
- [x] #3 ホスト機能フラグで Load More ボタンの表示可否が制御できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer.html にメッセージ名定数(_MSG_ZOOM_CHANGED/_MSG_REFERENCE_ACTIVATED/_MSG_FIND_OPTIONS_CHANGED/_MSG_SCROLL_POSITION_CHANGED/_MSG_LOAD_MORE_LINES)と、存在チェック込みの共通ヘルパー _mmdPostMessage(name, payload) を追加する。
2. 5箇所の postMessage 呼び出し(zoomChanged/referenceActivated/findOptionsChanged/scrollPositionChanged/loadMoreLines)をすべて _mmdPostMessage 経由に統一する。これにより referenceActivated のガード欠如(AC#2)も解消される。zoomChanged 呼び出しは「変化判定」と「送信可否判定」が混在していたのを分離し単純化する。
3. viewer.js に純粋関数 isHostFeatureEnabled(hostFeatures, key) を追加し(未注入時は true 扱い)、module.exports に追加してテスト可能にする。
4. viewer.html の _mmdSetTruncated() で Load More ボタン表示を isHostFeatureEnabled(window._mmdHostFeatures, 'loadMore') でガードし、keydown ハンドラで Space キーのページスクロールを isHostFeatureEnabled(window._mmdHostFeatures, 'spaceScroll') でガードする。
5. BefoldKit/ViewerBridge.swift に hostFeaturesScript(loadMore:spaceScroll:) を追加(デフォルト true/true、window._mmdHostFeatures を注入)し、befold/Viewer/ViewerWebView.swift で他の *StringsScript と同様に WKUserScript として注入する。
6. befoldTests/ViewerBridgeTests.swift の契約テストを新しい _mmdPostMessage / 定数パターンに合わせて更新し、hostFeaturesScript のテストを追加する。befold/Resources/__tests__/viewer.test.js に isHostFeatureEnabled の jest テストを追加する。
7. swift build / swift test / npx jest で回帰確認する。WKWebView 実描画は自動テスト対象外のため /webview-smoke で手動確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
viewer.html の5箇所の postMessage(zoomChanged/referenceActivated/findOptionsChanged/scrollPositionChanged/loadMoreLines)を、ハンドラ存在チェック込みの共通ヘルパー _mmdPostMessage(name, payload) に統一。ガードのなかった referenceActivated も自動的にガード付きになった(e.isTrusted チェックは維持)。ホスト機能フラグは BefoldKit/ViewerBridge.swift の hostFeaturesScript(loadMore:spaceScroll:) で window._mmdHostFeatures として注入し(デフォルト true/true)、viewer.js の純粋関数 isHostFeatureEnabled(hostFeatures, key) で Load More ボタン表示と Space キーのページスクロールを制御できるようにした。ViewerBridgeTests の契約テストを新パターンに合わせて更新し、hostFeaturesScript のテスト・jest の isHostFeatureEnabled テストを追加。security-reviewer による確認でも Critical/High/Medium な指摘なし(既存の isTrusted ガード・CSP・innerHTML 経由レンダリングによる script 不実行はいずれも維持)。検証: swift build 成功、swift test 371件全通過、npx jest 197件全通過、scripts/webview-smoke.swift PASS。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer.html の postMessage 呼び出し5箇所を共通ヘルパー _mmdPostMessage に一本化し、ガード欠如だった referenceActivated も解消した。BefoldKit/ViewerBridge.swift に hostFeaturesScript を追加し window._mmdHostFeatures 経由でホスト機能フラグ(Load More ボタン表示・Space キースクロール)を制御可能にした。swift test(371件)/jest(197件)/webview-smoke/security-review で回帰なしを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
