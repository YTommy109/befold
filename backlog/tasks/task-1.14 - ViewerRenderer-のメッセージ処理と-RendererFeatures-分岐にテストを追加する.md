---
id: TASK-1.14
title: ViewerRenderer のメッセージ処理と RendererFeatures 分岐にテストを追加する
status: To Do
assignee: []
created_date: '2026-07-19 02:56'
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
- [ ] #1 5 種の postMessage メッセージのデコードとディスパッチがユニットテストで検証されている
- [ ] #2 不正な body（型不一致・欠落）が無視されることがテストされている
- [ ] #3 allowsInteractiveBridging=false のとき referenceActivated / loadMoreLines がハンドラ登録されないことがテストされている
<!-- AC:END -->
