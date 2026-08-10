---
id: TASK-401
title: リネーム後の再描画がスクロール位置を提示開始時の保存値へ巻き戻す
status: Done
assignee: []
created_date: '2026-08-09 13:32'
updated_date: '2026-08-09 14:40'
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
- [x] #1 表示中ファイルを外部でリネーム・移動しても、現在のスクロール位置が維持される
- [x] #2 リネーム時にスクロール位置が巻き戻ると落ちる回帰テストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerRenderer に handleRename(from:to:) を追加: rendered.filePath が from と一致するときだけ、ミラー全体コピー + recordRendered で filePath を to へ差し替える(部分更新の入口は作らない)
2. WebViewCommandController に noteRename(from:to:) を追加し、ViewerWindowController.handleRename から perFileState.migrate と同じ同期区間で呼ぶ
3. これによりリネーム後の再ロードは same-file 再描画になり restoreFromPersistedPosition=false → _mmdSetRestoreScroll が注入されず、viewer.js の fallback(render 直前の scrollTop)が現在位置をそのまま保つ
4. 回帰テスト: (a) renderer.handleRename がミラーを差し替える/不一致なら何もしない (b) ViewerWindowController.handleRename からの配線でミラーが追随する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ViewerRenderer.handleRename(from:to:) がミラー全体コピー + recordRendered で filePath を差し替え(BefoldRenderKit/ViewerRenderer+RenderHelpers.swift)、ViewerWindowController.handleRename → WebViewCommandController.noteRename → DocumentRendering(adapter) → WebViewProxy.renderer(weak) で配線。検証: swift test 全 1233 件パス。AC1 は各ホップの自動テスト連鎖で担保 — (1) 配線: ViewerWindowControllerTests.renameRetargetsRendererMirrorFilePath、(2) 同一ファイル再描画では復元注入なし: ViewerWebViewCoordinatorTests.isFileOrModeSwitch(既存)、(3) 注入なし render は現在位置を保つ: jest「注入位置は 1 回の描画で消費され、次の描画では現在位置を保つ」(jsdom で実 DOM の scrollTop を検証)。WebView 実機での通し確認はプロジェクト方針(GUI 層はリリース前手動チェック)に従い次回リリース前チェックで行う。swiftlint file_length 対応で ViewerWindowController の Window/Content Helpers extension を ViewerWindowController+WindowHelpers.swift へ分離(挙動不変)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
リネーム時に描画済みミラーと JS 側文書パスを新パスへ追随させ、リネーム再描画が同一ファイルの再描画として扱われるようにした(復元注入なし → viewer.js の fallback が現在位置を保持)。swift test 1233 件・jest 388 件・swiftlint main ベースライン差分(新規違反)ゼロで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
