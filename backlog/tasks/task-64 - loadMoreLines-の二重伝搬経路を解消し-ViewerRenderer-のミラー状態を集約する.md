---
id: TASK-64
title: loadMoreLines の二重伝搬経路を解消し ViewerRenderer のミラー状態を集約する
status: To Do
assignee: []
created_date: '2026-07-19 02:57'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 33000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
続き読み込み（loadMoreLines）は JS postMessage → ViewerRenderer+RenderHelpers.swift:10-44 → ViewerStore.loadMoreLines（befold/Viewer/ViewerStore.swift:175-208）で content / contentRevision を書き換えるため、同じ更新が (a) コールバック戻り値経由の appendChunk と (b) @Observable 経由の SwiftUI 再評価の両方で renderer に届く。全文 render の誤爆を防ぐため renderer が recordRendered を先行同期する繊細なレース回避（RenderHelpers.swift:22-28 のコメント参照)が必要になっており、「同じ状態を 2 経路で伝搬」の典型例。伝搬経路を一本化してレース回避コードを構造的に不要にする。あわせて ViewerRenderer の lastRendered* 6 ミラー状態（BefoldRenderKit/ViewerRenderer.swift:33-42、「セットで必ずリセット」規約が doc コメント頼み :184-190）を 1 つの struct に束ね、一括破棄できる形にする。2026-07-19 のアーキテクチャレビュー（データフロー観点）で特定。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 続き読み込みの結果が renderer へ届く経路が 1 本になっている
- [ ] #2 recordRendered の先行同期によるレース回避コードが不要になっている
- [ ] #3 lastRendered* のミラー状態が 1 つの型に集約され、一括リセットできる
- [ ] #4 既存の ViewerStore チャンク系テストが通過する
<!-- AC:END -->
