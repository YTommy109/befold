---
id: TASK-136
title: ViewerToolbarController のツールバー状態同期を単一化し item 記述を宣言的にする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:41'
updated_date: '2026-07-25 04:29'
labels:
  - refactor
  - structural
  - app
dependencies: []
priority: medium
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
「ツールバーが現在状態を反映する」不変条件を、各変更点で無効化対象の item サブセットを手作業で列挙して維持している。store.onContentReloaded は 3 item 全て、toggleLineNumbers/toggleBookmark は各 1 item、applySourceMode は modeToggle+lineNumbers のみ(bookmark 抜け)、ViewerWindowManager.applyDisplayOverrides は CLI 経路で間接発火に依存、と散在する。新 item や新規状態変更のたびに N 箇所を触る必要があり抜けが silent。加えて ViewerToolbarController(約299行)は update*ToolbarItem 3 メソッドの guard/lookup 定型と make*ToolbarItem の NSButton+menuFormRepresentation 定型(3 箇所コピペ)が重複し、item の identity(identifier/symbol/label/action/更新規則)が builder と updater に分散している。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 状態から全ツールバー item を再同期する単一の refreshToolbarState() 相当のチョークポイントが導入され、各変更点はそれを呼ぶだけになる(個別 update* は private 化)
- [x] #2 item の identifier/symbol/label/action/更新規則を 1 箇所で宣言する記述(ToolbarItemSpec 相当)へ集約され、menuFormRepresentation の定型重複が解消している
- [x] #3 ツールバー item・状態の追加時に触る箇所が単一化されている(新規 item 追加が 1 箇所で完結)
- [x] #4 swift build/test・webview-smoke が通り、ツールバー表示に回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. テスト先行: ViewerWindowControllerToolbarTests に (a) 外部変更後 refreshToolbarState() で bookmark/行番号/モード切替が一括再同期される (b) applyDisplayOverrides(showLineNumbers:) が行番号アイテムへ反映される(現行の抜け) (c) モード切替セグメントの有効/選択マトリクス を追加し失敗を確認する
2. ViewerToolbarController に ToolbarItemSpec(identifier/シンボル/ラベルキー/action/menu action/isNavigational/状態反映)の静的テーブルを導入し、makeItem を単一の汎用ビルダーへ統合(menuFormRepresentation の 3 箇所コピペを解消)
3. refreshToolbarState() を単一チョークポイントとして追加し、個別 update* を private 化。呼び出し側(onContentReloaded / applySourceMode / toggleLineNumbers / toggleBookmark / historyStateDidChange)は refreshToolbarState() のみ呼ぶ
4. ViewerWindowManager.applyDisplayOverrides から ViewerWindowController.refreshToolbarState() を呼び、CLI 経路の間接発火依存を解消
5. swift build / swift test / /check / webview-smoke で回帰確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ViewerToolbarController に ToolbarItemSpec(identifier/labelKey/view 種別+シンボル/action/menuAction/isNavigational/applyState)と、その並びが既定表示順になる layout テーブルを導入。toolbarDefaultItemIdentifiers / toolbarAllowedItemIdentifiers / itemForItemIdentifier / refreshToolbarState はすべて layout から導出するため、アイテム追加は layout の 1 要素追加で完結する。makeItem/makeView に生成を統合し menuFormRepresentation の 3 箇所コピペを解消。

単一チョークポイント: refreshToolbarState() が全ライブアイテムへ applyState を適用。個別 update* は applyHistoryState/applyModeToggleState/applyLineNumbersState/applyBookmarkState として private 化。呼び出し側は onContentReloaded・applySourceMode・toggleLineNumbers・toggleBookmark・historyStateDidChange いずれも refreshToolbarState() のみ。副産物として applySourceMode のブックマーク抜けと ViewerWindowManager.applyDisplayOverrides の行番号ツールバー未更新(間接発火依存)を解消。

検証: swift build ok / swift test 633 tests 全通過 / npx jest 266 PASS / webview-smoke PASS。新規テストは追加時にコンパイル失敗(RED)を確認し、モード切替テストは applyModeToggleState を早期 return させる変異で 3 件失敗することを確認済み。GUI の目視確認は未実施(規約どおりリリース前手動チェック対象)。

途中で気付いた点: 汎用ビルダー化の初版でボタン画像の accessibilityDescription が nil になっていたため、ラベルを渡すよう修正。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ツールバーの状態同期を refreshToolbarState() の単一チョークポイントへ集約し、アイテムの identity を ToolbarItemSpec の宣言テーブル(layout)へ一元化した。既定順・許可アイテム・生成・再同期はすべて layout から導出するため、アイテム追加時に触る箇所は 1 要素の追加のみ。副産物として applySourceMode のブックマーク更新漏れと applyDisplayOverrides の行番号ツールバー未反映を解消。swift build / swift test(633) / jest(266) / webview-smoke がすべて通過し、追加テスト(モード切替マトリクス・外部ブックマーク変更の再同期・行番号オーバーライドのツールバー反映)は変異注入で検知力を確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
