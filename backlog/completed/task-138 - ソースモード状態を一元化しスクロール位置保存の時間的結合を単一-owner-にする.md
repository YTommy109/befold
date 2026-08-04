---
id: TASK-138
title: ソースモード状態を一元化しスクロール位置保存の時間的結合を単一 owner にする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 22:41'
updated_date: '2026-07-25 06:01'
labels:
  - refactor
  - structural
  - app
dependencies: []
priority: medium
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
VWC.isSourceMode は store.isSourceMode の純粋なミラーで、モード変更は setSourceMode→applySourceMode→resetSourceMode を流れ各所で perFileState.sourceMode を永続化し、applySourceMode の 4 呼び出し点がそれぞれツールバー fan-out を記憶する。また 遷移前に退出モードのスクロール位置を保存する idiom(webViewCommands.saveCurrentScrollPosition(..., mode: isSourceMode ? .source : .rendered))が performFileSwitch と setSourceMode の 2 箇所で同一表現で複写され、順序ハザードを説明する同趣旨コメントが重複している。save-then-mutate の順序制約が各変更点の暗黙プロトコルになっている。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 save-before-mutate のスクロール保存が単一のエントリ(例: beginTransition(savingScrollFor:) か applySourceMode/performFileSwitch の共有入口)へ集約され、複写が解消している
- [x] #2 VWC.isSourceMode の重複ミラーが見直され、ソースモード状態の所在が一元化されている(可能なら store.isSourceMode を直接参照)
- [x] #3 swift build/test・webview-smoke が通り、モード切替・ファイル切替時のスクロール位置復元に回帰がない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
0. 調査で判明した前提: AC#2 の「VWC.isSourceMode の重複ミラー」は既に解消済み(cade9a02, 2026-07-19 で store 委譲の computed property 化。起票時の記述が古い)。残る実作業は AC#1 の複写解消と、ソースモード状態の所在をさらに絞る小さな整理。
1. 単純化の先出し: Bool → ViewerBridge.ViewMode の写像(三項式)が VWC 2 箇所・ViewerContentView・ViewerRenderer+RenderHelpers の計 4 箇所に散っている。ViewerBridge.ViewMode に init(isSourceMode:) を追加して写像を 1 箇所にする。
2. save-before-mutate を単一エントリへ集約する。VWC に private func saveScrollPositionBeforeTransition() を設け、退場側(現在の URL・現在のモード)の確定保存と順序ハザードの説明をそこだけに置く。performFileSwitch と setSourceMode はこれを呼ぶだけにし、重複コメントを削除する。
3. WebViewCommandController.saveCurrentScrollPosition のコメントから重複した順序ハザード説明を外し、キー指定の責務だけを述べる(タイミング制約は呼び出し側の owner が担うと明記)。
4. ソースモード状態の所在を絞る: 未使用の ViewerToolbarHost.isSourceMode 要件を削除する(ツールバーは store.showsCodeContent 経由でしか参照していない)。あわせて setSourceMode/applySourceMode/resetSourceMode/canToggleSourceMode を NSWindowDelegate 適合 extension から専用の Source Mode extension へ移し、owner の所在を分類上も一致させる。実際には rename 時のみ呼ばれる resetSourceMode の誤ったコメント(ファイル切り替え時)も直す。
5. 検証: swift build / swift test / npx jest / webview-smoke。ViewMode(isSourceMode:) の写像テストを追加。モード切替・ファイル切替時のスクロール位置復元は手動確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 
- ViewerBridge.ViewMode に init(isSourceMode:) を追加し、Bool → ViewMode の写像を 1 箇所へ集約(VWC・ViewerContentView・ViewerRenderer+RenderHelpers に散っていた三項式を解消)。
- VWC に private saveScrollPositionBeforeTransition() を新設。退場側(現在の URL・現在のモード)の確定保存と save-before-mutate の順序ハザードの説明をここだけに置き、performFileSwitch と setSourceMode は呼ぶだけにした。performFileSwitch の for: oldURL は、この時点で fileURL == oldURL(applyURLToWindow/openFile は後)のため等価。
- WebViewCommandController.saveCurrentScrollPosition のコメントから重複した順序ハザード説明を外し、キー指定だけを担いタイミングの判断は呼び出し側が負うと明記。
- 未使用だった ViewerToolbarHost.isSourceMode 要件を削除(ツールバーは store.showsCodeContent 経由でのみ参照)。ソースモード関連(setSourceMode/applySourceMode/resetSourceMode/canToggleSourceMode + 新設の保存入口)を NSWindowDelegate 適合 extension から専用の Source Mode extension へ移動。
- resetSourceMode の実態と合わないコメント(ファイル切り替え時)をリネーム時の強制リセットに修正。

検証: swift build OK、swift test 638 件 PASS(ViewMode(isSourceMode:) の写像テストを追加)、npx jest 284 件 PASS、webview-smoke PASS。
注意: saveCurrentScrollPosition は WKWebView 実体を要するため自動テスト不能(WebViewCommandControllerTests に既記載)。切替時のスクロール位置復元は手動確認で担保する。

手動確認(今回の変更を含む再ビルド版で実施): 同一ファイル内のプレビュー⇄ソース切替でモードごとにスクロール位置が独立して保たれること、別ファイルへ切替して戻ると元の位置へ復元されることを確認。回帰なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
退場側スクロール位置の確定保存(save-before-mutate)が performFileSwitch と setSourceMode に同一表現で複写され、順序ハザードのコメントも重複していた問題を、単一の入口 saveScrollPositionBeforeTransition() へ集約して解消した。あわせて Bool → ViewerBridge.ViewMode の写像を ViewMode(isSourceMode:) の 1 箇所に集約し、未使用だった ViewerToolbarHost.isSourceMode 要件を削除、ソースモードの owner ロジックを NSWindowDelegate 適合 extension から専用 extension へ移した。AC#2 の VWC.isSourceMode の重複ミラーは着手時点で既に store 委譲の computed property になっており(cade9a02)、起票文が古い状態を写していたため、所在をさらに絞る方向で対応した。検証は swift build OK、swift test 638 件 PASS(ViewMode(isSourceMode:) の写像テストを追加)、npx jest 284 件 PASS、webview-smoke PASS、および再ビルド版アプリでのモード切替・ファイル切替のスクロール位置復元の手動確認。
<!-- SECTION:FINAL_SUMMARY:END -->
