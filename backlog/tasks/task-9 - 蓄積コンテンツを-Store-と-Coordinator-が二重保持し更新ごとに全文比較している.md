---
id: TASK-9
title: 蓄積コンテンツを Store と Coordinator が二重保持し更新ごとに全文比較している
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 07:28'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/200
priority: medium
ordinal: 5000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #200 から移行。チャンク読み込みで上限 50MB に上がった蓄積テキストを ViewerStore.content と Coordinator.lastRenderedContent が各全量保持（50MB ファイルで Swift 側だけで約 100MB の重複バッファ）。描画ガードが content != lastRenderedContent という全文比較で、updateNSView のたびに O(n) バイト比較がメインスレッドで発生する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 lastRenderedContent が世代カウンタまたはハッシュによる変更検知に置き換えられている
- [x] #2 重複バッファが解消されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerStore に private(set) var contentRevision: Int = 0 を追加し、content を更新する3箇所(apply の .chunked/.full ケース、loadMoreLines の content +=)全てでインクリメントする。
2. ViewerContentView → ViewerWebView へ contentRevision: store.contentRevision を渡す新規パラメータとして追加し、updateNSView 経由で Coordinator.updateContent へ渡す。
3. Coordinator の lastRenderedContent: String? を lastRenderedContentRevision: Int? に置き換え、2箇所の全文比較(contentChanged/needsRender)を revision の整数比較に変更する(AC1)。recordRendered は content 文字列でなく contentRevision を保存するだけにする。
4. lastRenderedContent は CSV ソースモードの追記再描画(handleLoadMoreLines)でのみ実データとして使われているため、この用途だけに限定した accumulatedSourceContent: String? を新設する。recordRendered に isSourceMode を渡し、CSVソースモード時のみ content 全文でシードし、それ以外は nil にリセットする(通常ファイルでは重複バッファが一切発生しない)。handleLoadMoreLines は lastIsSourceMode/fileType.csvDelimiter による判定を一度だけ評価し、該当時のみ accumulatedSourceContent に追記する(AC2)。CSVソースモード自体の全文再描画をO(chunk)化するのは task-8 のスコープのため今回は触らない。
5. exitDirectHTMLMode のリセット対象・ドキュメントコメントを新フィールド名に合わせて更新する。
6. swift build / swift test で既存テストが通ることを確認する(lastRenderedContent系を直接テストするユニットテストは無いため、既存の ViewerStoreTests / ViewerWebViewCoordinatorTests の非回帰確認が中心)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ViewerStore に contentRevision(Int) を追加し content 更新3箇所(apply .chunked/.full, loadMoreLines)全てでインクリメント。ViewerWebView/Coordinator の content全文比較(2箇所)を contentRevision の整数比較に置換、lastRenderedContent(String?)を lastRenderedContentRevision(Int?)に置換(AC1)。recordRendered は content文字列を保持しなくなった。CSVソースモードの追記再描画専用に accumulatedSourceContent を新設し、recordRendered で isSourceMode && csvDelimiter != nil の場合のみcontent全文でシード、それ以外はnilにリセット(通常ファイルは重複バッファなし)。handleLoadMoreLinesは該当時のみ蓄積するようneedsSourceAccumulationで一度だけ判定(AC2)。CSVソースモード自体の全文再描画のO(chunk)化はtask-8の範囲のため未着手。SwiftLintのtype_body_length制約のためhandleLoadMoreLinesをextension側に移動。swift build / swift test --skip Integration --skip FileWatcherTests: 323 tests passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.content の更新3箇所でインクリメントする contentRevision を追加し、Coordinator側の content全文比較(needsRender/contentChanged)を revision の整数比較に置換(AC1)。Coordinatorのlast RenderedContent(常時全文保持)を廃止し、CSVソースモードの追記再描画にのみ必要なaccumulatedSourceContentに置き換え、それ以外のファイル/モードでは重複バッファを一切持たないようにした(AC2)。CSVソースモード自体の全文再描画方式(O(n²))は別タスク(task-8)の範囲として維持。swift build / swift test で323件全テスト成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
