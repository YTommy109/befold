---
id: TASK-17
title: チャンク読み込み導入でファイル内検索が読み込み済み部分しかヒットしなくなった
status: Done
assignee: []
created_date: '2026-07-16 00:55'
updated_date: '2026-07-16 04:07'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/198'
priority: high
type: bug
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
チャンク読み込みにより初回 1000 行 / 1MB のみ DOM に載るため、Cmd+F が未読み込み部分にヒットしない。main では 10MB 未満のテキストは全量読み込み・全文検索可能だったため挙動の回帰。対応方針: (1) 検索時に全チャンク読み込み (2) 未読み込み領域の明示 (3) 意図したトレードオフとして設計ドキュメントに明記。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 検索時に全文が検索対象になる、または未読み込み領域があることが検索 UI に明示される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer.html: グローバル _mmdIsTruncated を追加し _mmdSetTruncated 内で更新。_mmdOpenFind() を分岐: truncated中は _mmdSetFindLoading(true) 表示 + loadAllLinesForSearch を postMessage。Swift 側の読込完了後 _mmdOnAllLinesLoaded() が呼ばれ、ローディング解除 + _mmdFindRun() を実行。
2. ViewerBridge.swift: loadAllLinesForSearchMessageName / allLinesLoadedScript を追加。findStringsScript() に loadingAll キーを追加。
3. Localizable.xcstrings: viewer.find.loadingAll (en/ja) を追加。
4. ViewerWebView.swift: 新メッセージハンドラを makeNSView/dismantleNSView に登録・解除。Coordinator.handleLoadMoreLines の1チャンク適用ロジックを applyLoadedChunk(_:webView:) に抽出し、新規 handleLoadAllLinesForSearch() が onLoadMoreLines() を isTruncated=false になるまでループ適用、最後に allLinesLoadedScript を評価する(既存 isLoadingMoreLines フラグで二重起動をガード)。
5. テスト: ViewerBridgeTests に新メッセージ名/スクリプト定数/findStringsScript の loadingAll キー検証、bridgeFunctionsExistInViewerHTML への追記を行う。Coordinator のループ処理自体は WebView/GUI 層のため既存 handleLoadMoreLines 同様に自動テスト対象外とし、/webview-smoke で手動確認する。
6. /l10n-check で翻訳漏れがないか確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test --skip Integration --skip FileWatcherTests: 323 tests 全パス(ViewerBridgeTests に新規契約検証を追加)。/webview-smoke(BefoldApp/BefoldKit/Resources 指定)PASS。加えて独自の一時スクリプトで、検索バーを開いた時点で truncated=true の場合に loadAllLinesForSearch が postMessage され、入力欄が無効化→読込中表示になり、_mmdOnAllLinesLoaded() 完了後は入力欄が再有効化されて追記済みチャンク内の文字列も検索でヒットする(1/1)ことを確認した。/webview-smoke のデフォルト対象パスが実際の viewer.html の場所(BefoldKit/Resources)と不一致で引数省略時に timeout する既存の不具合を発見し、TASK-18 として別途起票した(本タスクのスコープ外)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
検索バー(Cmd+F)を開いた時点でファイルが段階読み込み中の場合、Swift 側 Coordinator.handleLoadMoreLines(untilFullyLoaded:) が残り全チャンクを読み終えるまでループ適用し、完了を _mmdOnAllLinesLoaded() で JS へ通知して再検索させることで、検索対象が未読み込み部分を含む全文になるよう修正した。ViewerBridge に loadAllLinesForSearchMessageName / allLinesLoadedScript / findStringsScript の loadingAll キーを追加し、viewer.html 側は _mmdIsTruncated を追跡して _mmdOpenFind() を分岐、読込中は検索入力欄を無効化してローディング表示する。ViewerWebView.swift のメッセージハンドラ登録/解除も配列駆動に統合して重複を解消した。ViewerBridgeTests にブリッジ契約の検証を追加(全323テストパス)、l10n-check で翻訳漏れなし、/webview-smoke で既存回帰なしを確認、専用の一時スクリプトで検索+全チャンク読込の往復動作を実地確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
