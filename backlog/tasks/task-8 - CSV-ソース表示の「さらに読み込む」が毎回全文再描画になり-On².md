---
id: TASK-8
title: CSV ソース表示の「さらに読み込む」が毎回全文再描画になり O(n²)
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 08:40'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/199
priority: medium
ordinal: 6000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #199 から移行。CSV をソース（レインボー）表示している場合、「さらに読み込む」のたびに蓄積済みコンテンツ全体を renderScript で再描画している。非 CSV パスは appendChunkScript で O(chunk) の追記になっており、CSV ソースモードも追記パスを使えるように JS 側を拡張する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CSV ソースモードも追記パス（appendChunk）を使用している
- [x] #2 全文再描画の特例コードが撤去されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現状調査: ViewerWebView.swift の handleLoadMoreLines/recordRendered が CSV ソースモード(レインボー表示)時のみ accumulatedSourceContent に全文を蓄積し renderScript で毎回全文再描画していることを確認。appendChunkScript 自体は CSV かどうかに依存しない汎用実装であること、LineChunkReader が respectsCSVQuotes: fileType.csvDelimiter != nil で既にクオート跨ぎの安全なチャンク分割を保証していることを確認。
2. 単純化検討: 新たな状態を増やさず、viewer.html の appendChunk() に CSV ソース表示(pre code.csv-source)用の追記分岐を追加し、Swift 側の全文再描画特例(accumulatedSourceContent, needsSourceAccumulation)を削除して常に appendChunkScript を使う経路に一本化する方針を採用。既存の非CSVコードパスの行番号継続結合ロジック(buildLineNumberRows / 強制分割時の行結合)をそのまま流用できることを確認したため、新規ロジックはCSV行の着色HTML生成のみに限定。
3. viewer.js: renderCsvSourceHtml から着色行生成ロジックを csvSourceInnerHtml(content, delimiter) として抽出・エクスポート(renderCsvSourceHtml は本体不変・委譲するだけ)。
4. viewer.html: appendChunk() で type==='csv' のとき実DOMを見て診断(pre code.csv-source があればソース表示、なければ既存のtbody追記=テーブル表示)。ソース表示時は csvSourceInnerHtml を使い、既存の非CSVコードパスの行番号テーブル追記/強制分割継続ロジックをそのまま共有する。
5. Swift側: ViewerWebView.swift から accumulatedSourceContent プロパティ、needsSourceAccumulation 判定、全文 renderScript 分岐、recordRendered の content/isSourceMode 引数を削除し appendChunkScript のみを使う経路に統一。
6. テスト: viewer.test.js に csvSourceInnerHtml のユニットテストを追加(renderCsvSourceHtml との整合性、空文字列、着色出力)。Node上で追記パス相当のシミュレーション(chunk1→startLine計算→chunk2)がフル再描画結果とバイト一致することを確認。
7. 検証: swift build / swift test --skip Integration --skip FileWatcherTests(323件)、npx jest(185件)が全てパスすることを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証結果:
- swift build: 成功(エラー0、既存の evaluateJavaScript 警告のみ)
- swift test --skip Integration --skip FileWatcherTests: 323件全てpass
- npx jest (BefoldApp): 185件全てpass(既存182件+新規3件: csvSourceInnerHtmlのユニットテスト)
- Node上での手動シミュレーション: CSV(行番号あり)を2チャンクに分けてbuildLineNumberRowsで追記した結果と、renderCsvSourceHtmlによる全文再描画結果がバイト単位で一致することを確認(MATCH: true)。行番号・レインボー配色ともにチャンク境界をまたいで正しく継続することを裏付けた。
- grep で accumulatedSourceContent / needsSourceAccumulation の参照が0件であることを確認(全文再描画特例コードの完全撤去)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CSV ソース表示(レインボー表示)の「さらに読み込む」を、appendChunkScript による追記パスに統一した。viewer.js の renderCsvSourceHtml から着色行生成ロジックを csvSourceInnerHtml として抽出し、viewer.html の appendChunk() で type==='csv' の際に実DOM構造(pre code.csv-source の有無)を見てテーブル表示/ソース表示を判定、ソース表示時は既存の非CSVコードパスと同じ行番号継続結合ロジックを共有する形で追記するよう拡張した。Swift 側(ViewerWebView.swift)の全文再描画特例(accumulatedSourceContent バッファ・needsSourceAccumulation 判定・renderScript 全文再描画分岐)を削除し、常に appendChunkScript を呼ぶ経路に一本化(11行追加・43行削除の純減)。viewer.test.js に csvSourceInnerHtml の単体テストを追加。swift test 323件・jest 185件が全てpassし、追記パスとフル再描画のNode上シミュレーションでHTML出力がバイト一致することを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
