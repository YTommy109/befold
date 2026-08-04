---
id: TASK-42
title: CSV クォート走査が Character 単位で行われ、NormalizedTextCache が回避した低速パスを再導入している
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 02:07'
updated_date: '2026-07-17 04:08'
labels: []
dependencies: []
priority: medium
type: enhancement
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
StringChunkReader.swift:56 の advanceRespectingQuotes は `for char in cache.text[lineStart ..< lineEnd] where char == "\\""` と書記素クラスタ(Character)単位で走査する。ViewerStore.swift:141 は CSV/TSV すべてで respectsCSVQuotes を有効にするため、巨大CSV(まさに 44cd255 が最適化した対象)の全行が Character 走査される。NormalizedTextCache 自身のドキュメントコメントが「Character 単位…の走査を避けることで大幅に高速化」と明記しており、その設計に反する回帰。

修正方向: `"` は U+0022 の単一ASCIIバイトで、UTF-8 のマルチバイト列に 0x22 は現れない(継続バイトは 0x80 以上)ため、text.utf8 のバイト走査で意味論的に等価。さらに深い案として、正規化パス(全バイトを一度走査済み)で行ごとのクォートパリティを記録すればリーダー側は O(1)/行にできる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CSV のクォート走査が Character イテレーションを使わない
- [x] #2 既存の StringChunkReader のクォート跨ぎテストが全て通る
- [x] #3 巨大CSVのチャンク読込時間が改善する(手元計測をノートに記録)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. StringChunkReader.advance のクォート走査を text.utf8 のバイト単位走査に置き換える(U+0022 はASCII単一バイトでマルチバイト継続バイトと衝突しないため意味論的に等価)
2. bytesScanned のインクリメントをバイト単位に統一する
3. 既存のクォート跨ぎテスト(csvQuotedNewline, withoutCSVQuotes, unbalancedQuoteLargeCSVIsChunked 等)を実行して回帰がないことを確認する
4. 巨大CSVでの読込時間を簡易計測し、改善をノートに記録する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
text.utf8 のバイト単位走査に置き換え(U+0022はASCII単一バイトのためマルチバイト継続バイトと衝突せず意味論的に等価)。既存のクォート跨ぎテスト全12件(StringChunkReaderTests)がパス。
計測: 50万行(各行 "field1,\"quoted, value\",field3,field4,field5\n")のCSVを respectsCSVQuotes=true で全読込した所要時間。
- 修正前(Character単位走査): 1.203s
- 修正後(UTF8バイト単位走査): 0.229s
約5.2倍高速化。計測はテスト対象コードに一時的なPerfScratchTestを追加して実施し、計測後に削除(コミットには含めない)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
StringChunkReader.advance のクォート走査を Character 単位から text.utf8 のバイト単位走査に置き換えた。U+0022 はASCII単一バイトでUTF-8マルチバイト継続バイト(0x80以上)と衝突しないため意味論的に等価。既存のクォート跨ぎテストを含む StringChunkReaderTests 12件、および全体テストスイート360件が全てパス。50万行CSVでの読込ベンチマークで 1.203s→0.229s (約5.2倍)の改善を確認(計測用コードはコミットに含めず削除済み)。
<!-- SECTION:FINAL_SUMMARY:END -->
