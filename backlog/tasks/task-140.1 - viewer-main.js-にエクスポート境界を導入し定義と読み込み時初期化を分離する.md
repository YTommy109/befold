---
id: TASK-140.1
title: viewer-main.js にエクスポート境界を導入し定義と読み込み時初期化を分離する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:42'
updated_date: '2026-07-25 02:19'
labels:
  - refactor
  - structural
  - js
dependencies: []
parent_task_id: TASK-140
priority: medium
ordinal: 55000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer-main.js に typeof module ガード付きのエクスポート面を設け(viewer.js と同型)、定義と読み込み時の初期化呼び出し(_mmdInit*() 等)を分離して、jsdom + viewer.html DOM 下でロジックを import 可能にする。以降のサブタスク(render 分岐抽出・find 状態カプセル化)のテスト到達点の前提。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 viewer-main.js が typeof module ガード付きでロジックをエクスポートし、副作用(即時 DOM 取得/リスナ登録)が初期化関数へ分離されている
- [x] #2 jsdom で viewer-main.js を import してもトップレベル副作用でエラーにならず、少なくとも 1 つの関数が単体テストから呼べる
- [x] #3 ブラウザ(WKWebView)での既存挙動に回帰がない(webview-smoke 通過)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 単純化検討: (a) ファイル全体を IIFE で包む案 → Swift 側 ViewerBridgeTests の文字列一致(署名・window._mmdInitialZoom 等)に影響はないが、全行のインデント変更で差分が巨大化し本質(副作用分離)が埋もれるため不採用。(b) ESM 化(type=module)案 → viewer.html は classic script 順次読み込みで viewer.js のグローバルに依存しており、CSP と読み込み順の前提を変えるため本サブタスクの範囲外。(c) 採用: viewer.js と同型の 'typeof module' ガード + トップレベル副作用の init 関数化。追加の状態も分岐も増やさず、既存の _mmdInit* 群の延長で表現できるため最小。

1. viewer-main.js のトップレベル副作用をサブシステムごとの init 関数へ移す:
   - _mmdInitKeyboard()      : keydown/keyup/window blur (88-133)
   - _mmdInitReferenceClicks(): #diagram-wrap click (136-170)
   - _mmdInitWheelZoom()     : document wheel (245-254)
   - _mmdInitResize()        : window resize (286-293)
   - _mmdInitColorScheme()   : matchMedia 取得(380) + change リスナ(437-444)
   - _mmdInitMarkdown()      : markdown-it セットアップ (447-486)
   - _mmdInitFindControls()  : find バー各要素のリスナ (730-754)
   - _mmdInitScrollNotify()  : document scroll (823)
   - _mmdInitLoadMore()      : mmd-load-more-btn click (878-881)
2. トップレベルで window を読む初期化子を遅延化:
   - _mmdLastPostedZoom(20) は ZOOM_DEFAULT で宣言し、_mmdInitZoom() 内で parseStoredZoom(window._mmdInitialZoom) を代入してから _mmdApplyZoom() を呼ぶ(現行の「初期値と一致するので通知しない」挙動を維持)。
   - _mmdDarkQuery(380) は null 宣言にし _mmdInitColorScheme() で代入。
3. 全 init をブラウザ実行順どおりに呼ぶ _mmdInit() を追加し、末尾を次の形にする:
   if (typeof module !== 'undefined' && module.exports) { module.exports = {...}; } else { _mmdInit(); }
   → ブラウザは従来どおり自動初期化、jest では副作用ゼロで require できる。
4. package.json に jest.testMatch = ['**/__tests__/**/*.test.js'] を追加(テスト用ヘルパーをテストとして拾わせないため)。
5. テストハーネス __tests__/support/viewerMainHarness.js を追加: viewer.html から JSDOM を構築(スクリプト実行なし)し、window.matchMedia 等 WKWebView 前提の API をスタブし、viewer.js → viewer-main.js の順に window.eval して両者の module.exports を返す。
6. __tests__/viewer-main.test.js を追加し、_mmdInit() 後に setViewMode/setLineNumbers/_mmdScrollTarget/_mmdSetTruncated/ズーム適用/_mmdPostMessage 等を単体検証する。
7. 検証: BefoldApp で npx jest / swift test(ViewerBridgeTests のドリフト検知) / scripts/webview-smoke.swift(AC#3)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装:
- viewer-main.js のトップレベル副作用をサブシステム別の init 関数へ集約(_mmdInitKeyboard / _mmdInitReferenceClicks / _mmdInitWheelZoom / _mmdInitResize / _mmdInitColorScheme / _mmdInitMarkdown / _mmdInitFindControls / _mmdInitScrollNotify / _mmdInitLoadMore)。全 init をブラウザ実行順どおりに呼ぶ _mmdInit() を追加。
- _mmdLastPostedZoom は ZOOM_DEFAULT で宣言し _mmdInitZoom() 内で代入。parseStoredZoom はクランプしないため、旧実装(未クランプ値で初期化 → applyZoom でクランプ)と通知有無が一致することを確認済み。
- _mmdDarkQuery は null 宣言にし _mmdInitColorScheme() で window.matchMedia を取得。
- 末尾を viewer.js と同型の 'typeof module' ガードにし、CommonJS では定義のみ公開・ブラウザでは _mmdInit() を即時実行。

テスト基盤:
- package.json に jest.testMatch = ['**/__tests__/**/*.test.js'] を追加(support 配下のヘルパーをテストとして拾わせないため)。
- __tests__/support/viewerMainHarness.js: JSDOM を runScripts: 'outside-only' で生成し(script タグは実行せず window.eval のみ jsdom realm で動く)、viewer.html の DOM 上に viewer.js → viewer-main.js を順に評価して両者の module.exports を返す。jsdom 未実装の window.matchMedia をスタブし、window.webkit.messageHandlers を差し替えて postMessage を記録するヘルパーも提供。

検証:
- npx jest: 220 passed(viewer-main.test.js 17 件を新規追加)
- swift test: 615 tests / 86 suites passed(ViewerBridgeTests の Swift↔JS ドリフト検知 32 件を含む)
- swift scripts/webview-smoke.swift: PASS(CSP 下で全スクリプト稼働・mmd/md 描画・外部画像/data: iframe ブロック・PDF blob 表示)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-main.js に viewer.js と同型の 'typeof module' エクスポート境界を導入し、読み込み時の副作用(DOM 取得・リスナ登録・注入値の反映)を 9 つの init 関数と _mmdInit() へ分離した。ブラウザ(WKWebView)は module が存在しないため従来どおり即時初期化、CommonJS からは副作用ゼロで読み込める。あわせて JSDOM(runScripts: 'outside-only')で viewer.html の DOM 上に viewer.js → viewer-main.js を評価するテストハーネスを追加し、初期化・ズーム通知・打ち切りバナー・検索バー配線の 17 件を新規テスト化した。検証: npx jest 220 passed / swift test 615 passed(ViewerBridgeTests のドリフト検知含む)/ webview-smoke PASS。
<!-- SECTION:FINAL_SUMMARY:END -->
