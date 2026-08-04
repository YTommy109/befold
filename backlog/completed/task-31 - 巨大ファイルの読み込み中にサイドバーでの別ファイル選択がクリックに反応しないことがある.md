---
id: TASK-31
title: 巨大ファイルの読み込み中にサイドバーでの別ファイル選択がクリックに反応しないことがある
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-16 13:44'
updated_date: '2026-07-16 15:32'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 40
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
巨大ファイル(SJIS CSV等)を表示中にサイドバーで軽量な別ファイルをクリックしても、即座には表示が切り替わらないことがある。数回クリックすると開けることがあり、処理継続中でクリックが無視されているのか、クリックイベント自体が伝わっていないのか切り分けが必要。メインスレッド(MainActor)がブロックされていないか、サイドバーのクリックハンドラとViewerStore.openFileの間で入力が取りこぼされていないかを調査する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 巨大ファイル読み込み中にサイドバーの別ファイルをクリックした際の挙動(取りこぼし/キューイング/ブロッキング)の原因が特定されている
- [x] #2 原因に応じた対処方針(クリックの取りこぼし防止、または処理中である旨の視覚的フィードバック)が決まっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. task-31.1で判明した根本原因(TextEncoding.detectEncoding内のNSString.stringEncoding(for:)がsniffLengthを無視してファイル全体を走査していた)を修正する
2. TDD: 大きなShift_JISデータでdetectEncodingが高速に完了することを保証する回帰テストを先に追加し、修正前に失敗することを確認する
3. BefoldKit/TextEncoding.swiftを修正し、NSString.stringEncoding(for:)の対象をdata.prefix(sniffLength)に限定する
4. 既存テスト(TextEncodingTests, NormalizedTextCacheTests, ViewerStoreTests等)が壊れていないことを確認する
5. 実機で24MB SJIS CSVを開いて修正前後の所要時間・表示結果を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
task-31.1の実測により、原因はMainActorブロックでもクリック取りこぼしでもなく、TextEncoding.detectEncoding()がsniffLength(8192バイト)を無視してNSString.stringEncoding(for:)をファイル全体に対して呼んでいたことによる異常な処理時間(23〜25MBのSJIS CSVで36〜59秒)と判明した。

単純化の検討: 新しい状態やクリックキュー等を追加する前に、既存のsniffLength定数(『バイナリ判定・エンコーディング判定に見る先頭バイト数』とコメントされているが、この呼び出しにだけ未適用だった)を一貫して適用するだけで解決できると判断した。

対応: BefoldKit/TextEncoding.swift の detectEncoding() で NSString.stringEncoding(for:) の対象を data.prefix(sniffLength) に変更。TDDで大きなSJISデータに対する速度回帰テスト(TextEncodingTests.swift)を先に追加し、修正前(8.3秒)→修正後(0.25秒)を確認。既存の333件のテストは全てpass。実機(24MB SJIS CSV)でも文字化けなく数秒で表示されることを確認した(修正前は40〜50秒以上)。

副次的に判明していた『loadContentが古いloadTaskを一度もキャンセルしない』点は、今回の主要因(sniffLength未適用)の修正により個々の読み込みが数百ms程度まで短縮されたため、実用上のCPU競合リスクは大幅に低下した。継続的に追記される巨大ファイルでの積み増しリスクは残るため、必要なら別タスクとして切り出すか判断する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
task-31.1のログ実測により、原因はMainActorブロックでもクリック取りこぼしでもなく、TextEncoding.detectEncoding()がsniffLength(8192バイト)を無視してNSString.stringEncoding(for:)をファイル全体に対して実行していたことによる異常な処理時間(23〜25MB SJIS CSVで36〜59秒)と判明した。既存のsniffLength定数をこの呼び出しにも一貫して適用する最小修正(BefoldKit/TextEncoding.swift)で対応。TDDで速度回帰テストを追加(修正前8.3秒→修正後0.25秒で失敗→成功を確認)。既存333件のテストは全てpass。実機の24MB SJIS CSVでも文字化けなく数秒で表示されることを目視確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
