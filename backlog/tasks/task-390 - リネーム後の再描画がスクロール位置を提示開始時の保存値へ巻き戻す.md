---
id: TASK-390
title: リネーム後の再描画がスクロール位置を提示開始時の保存値へ巻き戻す
status: To Do
assignee: []
created_date: '2026-08-09 13:32'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 506000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review high（fix/window-live-state ブランチ）の CONFIRMED 指摘。

`handleRename` は意図的に `beginPresentingDocument` を呼ばない（引き継ぐのは保存値ではなくライブ値、TASK-369）。しかしリネームによる再ロードで filePath が変わるため `ViewerRenderer` 側は file switch と判定し（isFileOrModeSwitch = true）、applyRender が `store.scrollPositionToRestore` を注入する。この値は提示開始時に読んだまま更新されないので、長い文書を途中までスクロールした状態で Finder からリネーム・移動すると、表示が提示開始時の位置（多くは先頭）へ飛ぶ。

ブランチ前は `ViewerContentView` が body 評価ごとに `ScrollPositionStore` から現在位置を再計算していたため、リネームでも位置が保たれていた（このブランチでの回帰）。

参照: BefoldApp/befold/App/ViewerWindowController.swift:407 付近（handleRename）、restoreScrollPositionScript の注入経路
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 表示中ファイルを外部でリネーム・移動しても、現在のスクロール位置が維持される
- [ ] #2 リネーム時にスクロール位置が巻き戻ると落ちる回帰テストがある
<!-- AC:END -->
