---
id: TASK-141
title: viewer-main.js の描画/ズーム状態を小さなレコードへ集約する
status: To Do
assignee: []
created_date: '2026-07-25 03:05'
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
- [ ] #1 ズーム状態(全体ズーム・直近通知値・ダイアグラム個別ズーム)がレコードまたはクロージャへ集約され、裸のモジュールグローバルが解消している
- [ ] #2 描画状態(直近コンテンツ/型/言語・表示モード・行番号表示・PDF blob URL・スクロール復元/デバウンス)が owner の明確な単位へ集約されている
- [ ] #3 集約した状態の読み書きが jsdom ハーネス経由で単体テストされている
- [ ] #4 ズーム(全体/個別)・カラースキーム変更時の再描画・表示モード切替・スクロール位置復元・PDF 切替時の blob URL 解放に回帰がない(jest + webview-smoke + 手動確認)
<!-- AC:END -->
