---
id: TASK-608
title: XSL を伴う大きな XML が truncated で XSLT 変換表示に入らない
status: To Do
assignee: []
created_date: '2026-09-09 08:52'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 888000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-596 で入れた XSLT 変換表示は、`ViewerScriptDispatcher` / `OneShotRenderer` が `allowsXSLT: !render.truncation.isTruncated` を渡すため、チャンク読み込みで打ち切られた XML では発火しない。`FileType.isChunkable` は `.xml` を true にしており、`StringChunkReader.linesPerChunk` は 1000 行なので、1000 行を超える XML はすべて対象外になる。

実測（e-Gov 法令XML 7 本の行数）: 日本国憲法 1,476 / 労働基準法 5,464 / 国家公務員法 8,602 / 労働基準法施行規則 10,100 / 国税通則法 12,159 / 民法 23,703 / 所得税法 305,415。最小の憲法でも閾値を超えるため、実在の法令XMLでは XSLT 経路が一度も通らない。TASK-597（法令標準XML の内蔵スタイルシート）はこの修正なしでは AC を満たせない。

打ち切った断片を変換できないこと自体は正しい（構文として閉じていない）。直すべきは「変換対象になる XML を打ち切ること」であって、打ち切り後に変換を許すことではない。XSL を解決できる XML はチャンクせず全文ロードする形にする（判定は `ViewerLoadPipeline` が chunked / full を選ぶ地点に置く。`FileType.isChunkable` はファイルを見られないため、そこには持たせない）。

全文ロードにするとサイズ上限が `NormalizedTextCache.maxFileSizeBytes` から `nonChunkableSizeLimit` へ移る。上限超過分は従来どおり `fileTooLarge` で弾かれる（所得税法 16MB はここに当たる見込み。実測して Notes に残すこと）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 XSL スタイルシートを解決できる XML は、1000 行を超えていてもチャンクされず XSLT 変換表示になる
- [ ] #2 XSL を解決できない XML は従来どおりチャンク読み込みで段階描画される（回帰なし）
- [ ] #3 サイズ上限を超える XML は fileTooLarge として弾かれ、実測値を Notes に記録する
- [ ] #4 上記 3 つを担保するユニットテストがあり、修正を戻すと落ちることを確認する
<!-- AC:END -->
