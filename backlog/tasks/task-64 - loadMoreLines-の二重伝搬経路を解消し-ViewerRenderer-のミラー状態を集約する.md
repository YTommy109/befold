---
id: TASK-64
title: loadMoreLines の二重伝搬経路を解消し ViewerRenderer のミラー状態を集約する
status: Done
assignee: []
created_date: '2026-07-19 02:57'
updated_date: '2026-07-19 04:22'
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
- [x] #1 続き読み込みの結果が renderer へ届く経路が 1 本になっている
- [x] #2 recordRendered の先行同期によるレース回避コードが不要になっている
- [x] #3 lastRendered* のミラー状態が 1 つの型に集約され、一括リセットできる
- [x] #4 既存の ViewerStore チャンク系テストが通過する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 方針: Design Y(updateContent を唯一の描画 sink に一本化)

### 単純化検討の結果
- Design X(content/isTruncated を @ObservationIgnored 化し contentRevision を append 時に増分しない)は Path B を構造的に消せるが、既存テスト loadMoreLinesReturnsIncrementedContentRevision(contentRevision の append 時増分)を壊す→AC#4 に抵触するため不採用。
- Design Y は contentRevision の増分契約を維持しつつ、描画経路を updateContent 1 本に集約する。

### 実装
1. ViewerRenderer の lastRendered* 6 ミラー(contentRevision/fileType/filePath/showLineNumbers/isSourceMode/truncation)を struct RenderedStateMirror に集約し reset() で一括破棄。exitDirectHTMLMode / reloadViewerHTML の個別リセットを mirror 経由に置換。
2. handleLoadMoreLines は appendChunk/truncated/recordRendered を自前で行わず、onLoadMoreLines の結果を pendingAppend(chunk,revision) としてステージするだけにする(レース回避の先行 recordRendered を削除)。
3. updateContent(唯一の sink)で pendingAppend が現 revision と一致し、ファイル/モード切替でない場合は appendChunk+truncated+ミラー更新(増分描画)を行い、そうでなければ従来の全文 render。pendingAppend は消費時にクリア。revision 不一致時は破棄して全文 render にフォールバック(順序仮定に依存せず、最悪でも全文描画で正しい=今より堅牢)。
4. LoadMoreLinesResult.contentRevision は Path=updateContent が使うため維持。

### テスト
- 既存 ViewerStore チャンク系テスト(contentRevision 増分含む)は不変で通過。
- ViewerRendererMessageHandlingTests の isLoadingMoreLines 同期セットも維持。
- 追加: updateContent が pendingAppend を消費して増分描画し二重描画しないこと、revision 不一致で全文フォールバックすることの単体テスト。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
調査完了: loadMoreLines の二重伝搬を確認。Path A=handleLoadMoreLines(callback戻り値→appendChunk 増分描画), Path B=@Observable content/contentRevision/isTruncated→SwiftUI→updateContent(全文render誤爆)。B は handleLoadMoreLines が append await 前に lastTruncation と recordRendered(contentRevision) を同期先行することで抑止(RenderHelpers.swift:16-28 のレース回避)。observer は ViewerContentView のみ。設計方針を Plan で検討中。

実装完了(Design Y)。検証: cd BefoldApp && swift test → 427 tests passed(既存424+新規3)。既存 ViewerStore チャンク系テスト(loadMoreLinesReturnsIncrementedContentRevision 含む)は不変で通過し contentRevision の append 時増分契約を維持。新規: handleLoadMoreLines が pendingAppend にステージすること・nil 時は非ステージ・RenderedStateMirror.reset の一括破棄。AC#1 描画経路: handleLoadMoreLines は appendChunk/truncated/recordRendered を評価せずステージのみ、実描画は updateContent(applyAppend)の1本に集約。AC#2: 先行 recordRendered/lastTruncation 同期を削除。revision 不一致時は全文 render にフォールバックし順序仮定に非依存(今より堅牢)。AC#3: lastRendered* 6値を ViewerRenderer.RenderedStateMirror に集約し exitDirectHTMLMode で rendered.reset() 一括破棄。

追補(Plan レビュー反映): pendingAppend を上書きではなく累積(連結)する形に修正。updateContent が消費する前に続き読み込みが合体した場合の DOM 追記漏れを防ぐ(旧実装は各 Task 内で即 appendChunk していたため取りこぼしなし→本リファクタでの回帰を予防)。累積の単体テストを追加し swift test 428 件通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
loadMoreLines の二重伝搬(コールバック戻り値経由の appendChunk と @Observable 経由の updateContent 全文 render)を解消。handleLoadMoreLines は次チャンクを pendingAppend にステージするだけにし、実描画は唯一の sink である updateContent が消費して増分追記(applyAppend)する形へ一本化。これにより先行 recordRendered によるレース回避コードを撤去。ViewerRenderer の lastRendered* 6 ミラーを RenderedStateMirror struct に集約し reset() で一括破棄可能にした。swift test で 427 件(既存424+新規3)通過で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
