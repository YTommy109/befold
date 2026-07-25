---
id: TASK-136
title: ViewerToolbarController のツールバー状態同期を単一化し item 記述を宣言的にする
status: To Do
assignee: []
created_date: '2026-07-24 22:41'
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
- [ ] #1 状態から全ツールバー item を再同期する単一の refreshToolbarState() 相当のチョークポイントが導入され、各変更点はそれを呼ぶだけになる(個別 update* は private 化)
- [ ] #2 item の identifier/symbol/label/action/更新規則を 1 箇所で宣言する記述(ToolbarItemSpec 相当)へ集約され、menuFormRepresentation の定型重複が解消している
- [ ] #3 ツールバー item・状態の追加時に触る箇所が単一化されている(新規 item 追加が 1 箇所で完結)
- [ ] #4 swift build/test・webview-smoke が通り、ツールバー表示に回帰がない
<!-- AC:END -->
