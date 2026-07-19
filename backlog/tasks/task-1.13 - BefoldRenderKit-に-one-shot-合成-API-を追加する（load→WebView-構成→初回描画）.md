---
id: TASK-1.13
title: BefoldRenderKit に one-shot 合成 API を追加する（load→WebView 構成→初回描画）
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 02:56'
updated_date: '2026-07-19 03:27'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: enhancement
ordinal: 30000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerLoadPipeline.Outcome を render 呼び出しへ変換する糊コードが app 層の ViewerStore.apply（befold/Viewer/ViewerStore.swift:256-296）と ViewerWebView（befold/Viewer/ViewerWebView.swift:76-86、contentRevision / TruncationState の組み立て）に分散しており、QuickLook 拡張はこの糊を再発明する必要がある。BefoldRenderKit に one-shot 用の合成 API（ファイル URL → ViewerLoadPipeline.load(oneShotLoad: true) → WebView 構成 → updateContent）を追加し、QL 実装の本体をほぼゼロにする。あわせて ViewerContentView → ViewerWebView の 15 引数バケツリレー（befold/Viewer/ViewerContentView.swift:34-55）をスナップショット struct 化で整理できる。2026-07-19 のアーキテクチャレビュー（QuickLook 事前レビュー）で特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BefoldRenderKit に、ファイル URL から WebView 構成と初回描画までを 1 呼び出しで行う API がある
- [x] #2 oneShotLoad: true かつ RendererFeatures でブリッジ無効の構成（QuickLook 想定）で動作する
- [x] #3 既存アプリの表示経路は挙動不変で、既存テストが通過する
- [x] #4 新 API の Outcome→描画変換（reject / truncation を含む）にユニットテストがある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldRenderKit に純粋な Outcome→描画変換を追加: ViewerLoadPipeline.Outcome を初回描画に必要な値(content/fileType/filePath/rejectReason/TruncationState)へ写す static 関数 oneShotRender(from:url:fileType:) と行数計算ヘルパを新設(ViewerRenderer+OneShot.swift)。chunked→firstChunk+isTruncated、full→content+rejectReason、missing→unsupportedFormat フォールバック。
2. one-shot 合成 API: @MainActor loadOneShot(url:...) を追加。ViewerLoadPipeline.load(oneShotLoad: true) → makeWebView(findOptionsPreference: nil) → oneShotRender 変換 → updateContent を1呼び出しで実行し、WKWebView と rejectReason を返す。RendererFeatures はブリッジ無効構成(QuickLook 想定)で動作。
3. TDD: 純粋変換(reject/truncation/chunked/full/missing)のユニットテストを追加(ViewerRendererOneShotTests)。
4. swift build && swift test で 415 件 + 新規が通ることを確認。既存 ViewerStore.apply / ViewerWebView 経路は変更せず挙動不変を維持。
5. ViewerContentView→ViewerWebView の 15 引数バケツリレーのスナップショット struct 化は低リスクなら追加、リスクがあれば記録に留める。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了。BefoldRenderKit/ViewerRenderer+OneShot.swift を新設: (1) 純粋変換 oneShotRender(from:url:fileType:) が Outcome を OneShotRender(content/fileType/filePath/rejectReason/TruncationState)へ写す。chunked→先頭チャンク+isTruncated+displayedLineCount、full→content+rejectReason、missing→unsupportedFormat フォールバック。(2) displayedLineCount(of:) ヘルパ(ViewerStore.updateDisplayedLineCount と同一規則)。(3) @MainActor loadOneShot(url:...) が load(oneShotLoad: true)→makeWebView(findOptionsPreference: nil)→updateContent を1呼び出しで実行し OneShotResult(webView, rejectReason) を返す。純粋変換は nonisolated static で WebView なしにテスト可能。befoldTests/ViewerRendererOneShotTests.swift に9件のユニットテスト追加(full reject/正常、chunked 切り詰め+行数、末尾途中行、missing、displayedLineCount 境界、loadOneShot のブリッジ無効構成+binary reject)。swift build 成功、swift test 424件(既存415+新規9)通過、挙動不変。ViewerStore.apply/ViewerWebView の既存経路は未変更。

スコープ判断: ViewerContentView→ViewerWebView の15引数バケツリレーのスナップショット struct 化は、ACに含まれず、かつ ViewerWebView(GUI層)が自動テスト対象外で挙動不変(AC#3)を回帰検出できないためリスクがある。QL本体ゼロ化は loadOneShot で達成済みのため、struct 化は本タスクでは着手せず follow-up 候補として記録に留める。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldRenderKit に one-shot 合成 API を追加。ViewerRenderer+OneShot.swift に、ファイル URL→ViewerLoadPipeline.load(oneShotLoad: true)→makeWebView→updateContent を1呼び出しで行う @MainActor loadOneShot(url:...) と、その中核の純粋変換 oneShotRender(from:url:fileType:)(Outcome→content/rejectReason/TruncationState)・displayedLineCount(of:) を実装。QuickLook 拡張はブリッジ無効(allowsInteractiveBridging: false)構成で本 API を呼ぶだけで本体をほぼゼロにできる。ViewerStore.apply/ViewerWebView の既存ライブ経路は未変更で挙動不変。検証: swift build 成功、swift test 424件(既存415+新規9)通過。新規テスト ViewerRendererOneShotTests が reject/truncation/chunked/full/missing の変換とブリッジ無効構成での WebView 構成を網羅。
<!-- SECTION:FINAL_SUMMARY:END -->
