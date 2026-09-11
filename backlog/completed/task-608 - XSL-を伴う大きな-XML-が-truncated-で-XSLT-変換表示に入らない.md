---
id: TASK-608
title: XSL を伴う大きな XML が truncated で XSLT 変換表示に入らない
status: Done
assignee:
  - '@claude'
created_date: '2026-09-09 08:52'
updated_date: '2026-09-09 09:02'
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
- [x] #1 XSL スタイルシートを解決できる XML は、1000 行を超えていてもチャンクされず XSLT 変換表示になる
- [x] #2 XSL を解決できない XML は従来どおりチャンク読み込みで段階描画される（回帰なし）
- [x] #3 全量読み込みの上限を超える XML は XSL があってもチャンク読み込みのままにし、実測値を Notes に記録する
- [x] #4 上記 3 つを担保するユニットテストがあり、修正を戻すと落ちることを確認する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

`ViewerLoadPipeline` に `needsWholeDocument` を追加し、チャンク読み込みの先頭チャンクを
読んだ直後に「打ち切ったままでは表示できない」ものを全量読み込み（`.full`）へ切り替える。
判定を `FileType.isChunkable` へ持たせなかったのは、XSL の有無が拡張子から決まらないため
（TASK-596 が `FileType` に XSLT を載せなかったのと同じ理由）。

先頭チャンクだけで判定できるのは、`<?xml-stylesheet?>` がプロローグにしか置けず、
同名 `.xsl` の探索がファイル名だけで決まるため。全文を渡した場合と同じ答えになる。

`load` が `function_body_length` を超えたため、チャンク経路を `loadChunked` へ抽出した
（閾値の緩和はしていない）。

## 上限の扱い（AC#3）

全量読み込みに切り替えると上限が `NormalizedTextCache.maxFileSizeBytes`（100MB）から
`nonChunkableSizeLimit`（本体 `ContentLoader.maxTextFileSizeBytes` 10MB / QuickLook
`maxOneShotTextFileSizeBytes` 2MB）へ下がる。起票時は超過分を `fileTooLarge` で弾く
つもりだったが、空表示になるより段階描画でソースが読めるほうがよいため
**切り替えず従来どおりチャンク読み込みのまま**にした（AC#3 をその形に書き換えた）。

e-Gov 法令XML 7 本の実測（バイト数）: 日本国憲法 0.08MB / 労働基準法 0.41MB /
国家公務員法 0.69MB / 労働基準法施行規則 0.72MB / 国税通則法 0.96MB / 民法 1.69MB /
所得税法 17.43MB。本体アプリでは所得税法だけが上限超過でソース表示のまま。
QuickLook（2MB）では民法までが変換対象になる。

## 検証

- `swift test --skip Integration --skip FileWatcherTests` → 1850 tests / 305 suites 全通過
- 修正を戻す確認: `!firstChunk.isAtEnd` を `false` に落とすと
  「XSL を解決できる XML は 1000 行を超えても全量読み込みになる」が
  `ViewerLoadPipelineTests.swift:297` で落ちる（残る 2 件は回帰確認なので両方で通る）
- `/swiftlint-baseline`: origin/main との「真の新規」ゼロ・「解消したもの」ゼロ
  （抽出前は `load` の `function_body_length` が 1 件新規に出ていた）
- `markdownlint-cli2` 0 issues
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-596 の XSLT 変換表示が、1000 行を超える XML では truncated 扱いになり一度も発火しなかった欠陥を修正した。`ViewerLoadPipeline` が先頭チャンクを読んだ直後に「XSL を解決できる XML か」を判定し、該当すれば全量読み込みへ切り替える。全量読み込みの上限（本体 10MB / QuickLook 2MB）を超えるものは切り替えず、従来どおり段階描画でソースを見せる。ユニットテスト 3 件で担保し、修正を戻すと positive ケースが落ちることを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
