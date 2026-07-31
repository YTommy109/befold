---
id: TASK-224
title: 画像 base64 埋め込み（renderableContent）を MainActor 外で実行する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:14'
updated_date: '2026-07-31 12:12'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 310000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerRenderer+RenderHelpers.swift の applyRender/applyAppend が MarkdownImageEmbedder.embedLocalImages（全行の正規表現走査 + キャッシュ未命中時は最大 50MB の readData + base64 化）を @MainActor 上で同期実行している。ウォームは先頭チャンク分のみで、2 チャンク目以降の append・ソース/プレビュー切替・画像変更時はコールドになる。renderableContent は既に nonisolated static なので、加工を Task.detached に逃がし evaluateJavaScript だけ MainActor に戻す。DataURICache は NSLock 保護済みで並行呼び出し可。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 render/append 時の画像埋め込み処理（正規表現走査・画像読み込み・base64 化）が MainActor 外で実行される
- [x] #2 複数チャンク・ソース切替・画像更新の各経路で埋め込み結果が従来と同等である
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerRenderer.swift: contentUpdateGeneration: Int を追加(ViewerStore.loadGeneration と同じレースガード用カウンタ)。
2. ViewerRenderer+ContentUpdate.swift: updateContent の先頭で contentUpdateGeneration += 1。
3. ViewerRenderer+RenderHelpers.swift: embeddedContent(_:fileType:filePath:isSourceMode:) async ヘルパーを追加し、Task.detached で renderableContent(画像埋め込み含む)を実行。applyRender/applyAppend を async化し、行番号・ソースモード・truncation の即時反映は同期のまま先頭に残し、embeddedContent の await 後に generation 一致を確認してから evaluateJavaScript(renderスクリプト)+ recordRendered を実行(不一致なら破棄)。
4. ViewerRenderer+ContentUpdate.swift: applyRender/applyAppend の呼び出し箇所を Task { @MainActor in await self.applyRender(...) } / applyAppend(...) に変更。
5. テスト: ViewerRendererContentUpdateTests に、遅延する FileReading フェイクを注入した MarkdownImageEmbedder で2回連続 updateContent を発火し、古い embed 結果が rendered を上書きしないことを検証するテストを追加。
6. WebView 実描画は project 規約により自動テスト対象外のため、リリース前に手動確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 885件全通過(Integration/FileWatcherTests除く)。SwiftLint 実行、変更ファイルに新規エラーなし(function_body_length は98行で閾値100未満)。レースガード(contentUpdateGeneration)の実効性は、遅延 FileReading フェイクを注入した専用テスト(staleImageEmbedDoesNotClobberNewerRender)で検証。WebKit 実描画自体は project convention によりGUI層自動テスト対象外、手動確認は未実施(リリース前推奨)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
applyRender/applyAppend を async 化し、embeddedContent(Task.detached)で MarkdownImageEmbedder.embedLocalImages の正規表現走査・画像読込・base64化を MainActor 外へ逃がした。ViewerRenderer に contentUpdateGeneration カウンタを追加し(ViewerStore.loadGeneration と同じ idiom)、updateContent 呼び出し時にスナップショットを RenderRequest/AppendRequest 経由で渡すことで、後続の updateContent に追い越された古い埋め込み結果が rendered ミラーを巻き戻さないようにした。テスト注入用に ViewerRenderer.imageEmbedder を追加。既存レーステスト(directHTMLExitSurvivesRaceDuringReload)と新規レーステストで検証、swift test 885件全通過。
<!-- SECTION:FINAL_SUMMARY:END -->
