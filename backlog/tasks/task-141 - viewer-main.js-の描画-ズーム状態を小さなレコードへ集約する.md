---
id: TASK-141
title: viewer-main.js の描画/ズーム状態を小さなレコードへ集約する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-25 03:05'
updated_date: '2026-07-25 05:34'
labels:
  - refactor
  - structural
  - js
dependencies: []
priority: medium
ordinal: 61000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-140.3 で find 状態は _createFindController() のクロージャへ閉じたが、描画とズームの状態は viewer-main.js のモジュールスコープに裸の var として残っている。

ズーム関連: _mmdZoom / _mmdLastPostedZoom(全体ズームと直近通知値)、_diagramZooms(ダイアグラム個別ズーム)。
描画関連: _lastContent / _lastType / _lastLang(カラースキーム変更時の再描画用)、_currentType、_viewMode、_showLineNumbers、_pdfBlobUrl(blob URL のライフサイクル)、_mmdPendingRestoreScroll / _mmdScrollDebounceTimer(スクロール復元と通知デバウンス)。

これらは _mmdApplyZoom / _mmdFitImage / _mmdUpdateDiagramScrollHeight / render / _renderSource / appendChunk / setViewMode / setLineNumbers / _mmdRestoreScrollPosition など多数の関数から横断的に読み書きされており、どの関数がどの状態の owner なのかがコード上で表現されていない。find と同様に小さなレコード(またはクロージャ)へ集約し、読み書きの入口を絞ることで、状態の owner を明示して単体テストの到達点を作る。

もともと TASK-140.3 の説明に含まれていたが、同タスクの受け入れ基準は find 状態のみを対象としていたため実施しなかった分。TASK-140 のモジュール化により viewer-main.js は jsdom で単体テスト可能になっており(__tests__/support/viewerMainHarness.js)、本タスクの検証基盤は整っている。

関連: TASK-138 は Swift 側(ViewerWindowController)のソースモード状態とスクロール位置保存が対象で、本タスクは JS 側の状態が対象。両者は同じ関心事の別レイヤーにあたるため、片方の設計がもう一方に影響しうる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ズーム状態(全体ズーム・直近通知値・ダイアグラム個別ズーム)がレコードまたはクロージャへ集約され、裸のモジュールグローバルが解消している
- [x] #2 描画状態(直近コンテンツ/型/言語・表示モード・行番号表示・PDF blob URL・スクロール復元/デバウンス)が owner の明確な単位へ集約されている
- [x] #3 集約した状態の読み書きが jsdom ハーネス経由で単体テストされている
- [x] #4 ズーム(全体/個別)・カラースキーム変更時の再描画・表示モード切替・スクロール位置復元・PDF 切替時の blob URL 解放に回帰がない(jest + webview-smoke + 手動確認)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 調査: viewer-main.js の裸のモジュール状態 12 個の読み書き対応を確定する(完了)。_currentType は _lastType と同時に同値が代入されるだけの重複であることを確認。
2. 単純化の先出し: _currentType を廃止して直近描画レコードの type() に統合する。clampZoom を _mmdApplyZoom から書き込み側(ズームストア)へ寄せ、apply を「読んで適用するだけ」にする。
3. ズーム状態を _createZoomState() のクロージャへ集約する(全体ズーム・直近通知値・ダイアグラム個別 Map)。公開は value()/step()/wheel()/reset()/adoptStored()/takePostable()/diagramValue()/diagramStep()/diagramWheel()/diagramReset() に絞る。zoomChanged 通知の判定(直近通知値との差分)は takePostable() に閉じる。
4. 直近描画レコードを _createDocumentState() へ集約する(content/type/lang + appendText)。カラースキーム再描画は rerender 経路から record 経由でのみ読む。
5. 表示オプションを _createViewOptions() へ集約する(viewMode/showLineNumbers)。setMode() がモード切替持ち越し(_mmdModeSwitch.mark)を内包し、setViewMode/setLineNumbers は薄い委譲にする。
6. PDF blob URL を _createPdfBlobHolder() へ集約する(issue/release)。render() 冒頭の解放は release() 呼び出しのみにする。
7. スクロール同期を _createScrollSync() へ集約する(pending 復元位置 + デバウンスタイマ)。render() 冒頭の「Swift 主導のときだけ保留通知を破棄する」条件は両方の状態を持つ owner 内の beginRender() に閉じる。
8. jsdom ハーネス経由の単体テストを追加する: ダイアグラム個別ズームの保持/リセット/再描画をまたぐ維持、カラースキーム変更時の再描画、行番号表示の反映、PDF から他型への切替での blob URL 解放、スクロール位置復元(pending/fallback)、デバウンス通知の破棄条件。
9. jest + swift build + /webview-smoke + 手動確認で回帰確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 裸のモジュールグローバル 12 個を 5 つの owner へ集約した。
- _mmdZoom (_createZoomStore): 全体ズーム・直近通知値・ダイアグラム個別 Map。zoomChanged の差分判定は takePostable() に閉じ、クランプを全書き込み経路へ寄せて _mmdApplyZoom から clampZoom を除去した(注入値が範囲外のときに補正値を Swift へ通知し直す挙動は adoptStored で保持)。
- _mmdDocument (_createDocumentState): 直近描画の content/type/lang。単純化として _currentType を廃止し type() に統合した(両者は render() で同値が同時に代入されるだけの重複で、mermaid のパースエラーは描画開始後にしか発火しないため等価)。
- _mmdViewOptions (_createViewOptions): 表示モードと行番号。モード切替持ち越しの mark は旧モードを知る setMode() に内包し、setViewMode は薄い委譲にした。
- _mmdPdfBlob (_createPdfBlobHolder): blob URL の issue/release。
- _mmdScroll (_createScrollSync): 注入復元位置と通知デバウンスタイマ。render() 冒頭の「Swift 主導のときだけ保留通知を破棄」条件を beginRender() に閉じた。
Swift から名前で呼ばれる入口(ViewerBridge 契約)はすべて薄い委譲として維持。

検証: jest 284 件 PASS(新規 17 件)。新規テストは変異挿入で検知力を確認済み(beginRender 無条件破棄 / revoke 省略 / 個別ズームの index 固定 / 直近型の固定 / ズーム通知の重複判定除去 / 追記の未反映 / 行番号の固定 / モード切替の常時持ち越し / 復元位置の未消費 = すべて fail、無変異は pass)。swift build OK、swift test 637 件 PASS、swift scripts/webview-smoke.swift PASS。
ViewerRenderer/RenderHelpers のコメントが参照していた旧 JS 変数名(_showLineNumbers/_viewMode)を _mmdViewOptions に更新した。

手動確認(実機 GUI): 全体ズーム(⌘+/-/0・Ctrl+ホイール)、図の個別ズーム(+/-/ラベルリセット)、ダークモード切替時の再描画、ソース表示・行番号切替、タブ切替でのスクロール位置復元、PDF と他形式の行き来を確認し回帰なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-main.js に残っていた裸のモジュールグローバル 12 個を、_mmdZoom(全体ズーム・直近通知値・個別ズーム) / _mmdDocument(直近描画の内容・型・区切り) / _mmdViewOptions(表示モード・行番号) / _mmdPdfBlob(blob URL の生成と解放) / _mmdScroll(注入復元位置・通知デバウンス)の 5 つのクロージャへ集約し、状態の owner と読み書きの入口を明示した。あわせて _currentType(直近型との重複)を廃止し、クランプを書き込み経路へ寄せ、2 状態を同時に見る判定を takePostable()/beginRender() として owner の内側へ移した。Swift から名前で呼ばれる入口は薄い委譲として維持し ViewerBridge の契約は不変。検証は jest 284 件 PASS(新規 17 件、9 種の変異挿入で検知力を確認)、swift build OK、swift test 637 件 PASS、webview-smoke PASS、および実機 GUI での目視確認。
<!-- SECTION:FINAL_SUMMARY:END -->
