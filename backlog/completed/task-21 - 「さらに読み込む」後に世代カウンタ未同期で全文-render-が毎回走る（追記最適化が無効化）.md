---
id: TASK-21
title: 「さらに読み込む」後に世代カウンタ未同期で全文 render が毎回走る（追記最適化が無効化）
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 10:54'
updated_date: '2026-07-16 16:06'
labels: []
dependencies: []
references:
  - BefoldApp/befold/Viewer/ViewerWebView.swift
  - BefoldApp/befold/Viewer/ViewerStore.swift
priority: high
type: bug
ordinal: 52
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 8ef7703 で content 比較を contentRevision 世代カウンタに置き換えた際、handleLoadMoreLines（ViewerWebView.swift:440-465）が appendChunk 送信後に lastRenderedContentRevision を更新しなくなった（v1.7.0 では lastRenderedContent?.append(result.chunk) でキャッシュ整合を保っていた）。ViewerStore.loadMoreLines は contentRevision += 1 するため（ViewerStore.swift:155-156）、直後の SwiftUI 更新で needsRender が必ず true になり、追記済み全コンテンツの完全 render() が毎クリック走る。追記パス最適化（TASK-8 の趣旨）が事実上無効。onLoadMoreLines の戻り値に新 revision を含める、または store.contentRevision を読んで recordRendered する等で追記後にカウンタを同期する。副次論点: SwiftUI コミットが appendChunk より先に走った場合はチャンクが二重表示されるレース（PLAUSIBLE、タイミング依存）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「さらに読み込む」1 クリックにつき JS 側の描画は appendChunk 1 回のみで、全文 render() が走らない
- [x] #2 検索用の untilFullyLoaded ループ中も同様に全文 render が発生しない
- [x] #3 チャンク二重表示レースの可能性が排除されている（追記後に revision 同期）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore.loadMoreLines() の戻り値タプルに contentRevision を追加し、現在の contentRevision を返す（成功時・エラー時とも）
2. ViewerWebView.onLoadMoreLines のクロージャ型（struct プロパティおよび Coordinator var）を新しいタプル型に合わせて更新する
3. Coordinator.handleLoadMoreLines() で、result 取得直後（次の await の前）に recordRendered(contentRevision: result.contentRevision, fileType:, filePath:) を呼び、lastRenderedContentRevision を同期する。これにより (a) 直後の SwiftUI 再描画で needsRender が false になり全文 render が走らなくなる、(b) 更新を JS 呼び出しより前に同期実行することでチャンク二重表示レースの窓を閉じる
4. ViewerStoreTests に contentRevision が返り値でインクリメントされることを検証するテストを追加、既存の loadMoreLines 系テストが壊れないことを確認
5. swift build / swift test で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
修正: ViewerStore.loadMoreLines() の戻り値を LoadMoreLinesResult 構造体化(SwiftLint large_tuple 対策)し、contentRevision フィールドを追加(追記後の世代番号)。ViewerWebView.Coordinator.handleLoadMoreLines() は result 取得直後・次の await(evaluateJavaScript)より前に recordRendered(contentRevision: result.contentRevision, ...) を同期実行し lastRenderedContentRevision を即座に同期。これにより(a)直後の SwiftUI 再描画で needsRender=false となり全文 render() 誤爆を防止、(b) JS 呼び出し前に同期更新することでチャンク二重表示レースの窓を閉じる。検証: ViewerStoreTests に loadMoreLinesReturnsIncrementedContentRevision を追加し、store.loadMoreLines() の戻り値 contentRevision が store.contentRevision と一致し呼び出しごとに増分することを自動テストで確認(全348テスト pass: swift test)。swiftformat --lint も変更ファイルでクリーン。Coordinator/WKWebView 層の実際の render()/appendChunk 呼び出し回数そのものは、本プロジェクトのテスト規約(WebView/GUI 層は自動テスト対象外・リリース前手動チェック)により自動検証対象外のため、recordRendered が result.contentRevision で同期される経路をコードレベルで追跡し、次の updateContent(contentRevision: store.contentRevision) 呼び出し時に lastRenderedContentRevision と一致することを確認した(コードトレースによる検証、実機 WebView 目視確認は未実施)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
handleLoadMoreLines() が appendChunk 送信後に lastRenderedContentRevision を更新していなかったため、ViewerStore.loadMoreLines() が毎回 contentRevision += 1 する結果、直後の SwiftUI 再描画で needsRender=true となり全文 render() が誤爆する不具合を修正。ViewerStore.loadMoreLines() の戻り値を LoadMoreLinesResult 構造体(chunk/isTruncated/lineCount/contentRevision)にし、Coordinator.handleLoadMoreLines() で result 取得直後・await の前に recordRendered(contentRevision: result.contentRevision, ...) を同期実行してキャッシュを同期。副次論点だったチャンク二重表示レースも、この同期更新を JS 呼び出しより先に行うことで窓を閉じた。検証: ViewerStoreTests に contentRevision 増分の回帰テストを追加し、swift test で全348テスト pass、swiftformat --lint もクリーンであることを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
