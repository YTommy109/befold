---
id: TASK-1.14
title: ViewerRenderer のメッセージ処理と RendererFeatures 分岐にテストを追加する
status: Done
assignee: []
created_date: '2026-07-19 02:56'
updated_date: '2026-07-19 03:16'
labels: []
dependencies: []
parent_task_id: TASK-1
priority: high
type: task
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JS→Swift 方向の postMessage デコード・ディスパッチ（BefoldRenderKit/ViewerRenderer+MessageHandling.swift:26-59、5 メッセージの body 型検証を含む）と、allowsInteractiveBridging=false 時に referenceActivated / loadMoreLines ハンドラを登録しない多層防御（BefoldRenderKit/ViewerRenderer.swift:128-139 messageHandlerNames(for:)）が未テスト。ViewerBridgeTests は Swift→JS 方向のみをカバーしている。QuickLook はまさにこの RendererFeatures 分岐に依存するため、事前リファクタ（TASK-1.13 等）の前に安全網としてテストを張る。2026-07-19 のアーキテクチャレビューで特定（dagayn knowledge_gaps でも未テストホットスポット上位）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 5 種の postMessage メッセージのデコードとディスパッチがユニットテストで検証されている
- [x] #2 不正な body（型不一致・欠落）が無視されることがテストされている
- [x] #3 allowsInteractiveBridging=false のとき referenceActivated / loadMoreLines がハンドラ登録されないことがテストされている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. befoldTests に ViewerRendererMessageHandlingTests.swift を新規追加(@testable import BefoldRenderKit)。\n2. WKScriptMessage をサブクラス化した StubScriptMessage(name/body を override)でメッセージを注入。\n3. userContentController(_:didReceive:) を直接呼び、5種のメッセージのディスパッチを公開クロージャ/状態で検証: zoomChanged→onZoomChanged, referenceActivated→onOpenReference, scrollPositionChanged→onScrollPositionChanged, findOptionsChanged→findOptionsPreference 書き戻し, loadMoreLines→handleLoadMoreLines(isLoadingMoreLines フラグで検証)。\n4. 不正 body(型不一致・キー欠落)でハンドラが呼ばれないことを検証。\n5. messageHandlerNames(for:) を allEnabled と allowsInteractiveBridging=false で検証(referenceActivated/loadMoreLines の登録有無)。\n6. swift build && swift test。プロダクションコードは変更しない想定。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
befoldTests/ViewerRendererMessageHandlingTests.swift を新規追加(13 テスト)。WKScriptMessage をサブクラス化した StubScriptMessage で JS→Swift メッセージを注入し、userContentController(_:didReceive:) を直接検証。5種のディスパッチ(zoom/reference/scroll/findOptions/loadMore)、不正 body の無視(型不一致・キー欠落・未知メッセージ名)、messageHandlerNames(for:) の allowsInteractiveBridging 分岐を検証。プロダクションコードは無変更。検証: swift test で全 415 テスト成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerRenderer の JS→Swift postMessage デコード・ディスパッチと RendererFeatures.allowsInteractiveBridging によるハンドラ登録の多層防御にユニットテスト(13件)を追加。ViewerRendererMessageHandlingTests.swift を新規作成し、プロダクションコードは無変更。swift test 全 415 テスト成功で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
