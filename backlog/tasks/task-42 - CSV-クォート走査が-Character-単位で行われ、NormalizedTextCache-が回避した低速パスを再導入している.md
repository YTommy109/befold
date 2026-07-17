---
id: TASK-42
title: CSV クォート走査が Character 単位で行われ、NormalizedTextCache が回避した低速パスを再導入している
status: To Do
assignee: []
created_date: '2026-07-17 02:07'
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
- [ ] #1 CSV のクォート走査が Character イテレーションを使わない
- [ ] #2 既存の StringChunkReader のクォート跨ぎテストが全て通る
- [ ] #3 巨大CSVのチャンク読込時間が改善する(手元計測をノートに記録)
<!-- AC:END -->
