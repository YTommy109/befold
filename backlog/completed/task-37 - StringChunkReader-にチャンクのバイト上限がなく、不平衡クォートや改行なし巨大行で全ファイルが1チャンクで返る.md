---
id: TASK-37
title: StringChunkReader にチャンクのバイト上限がなく、不平衡クォートや改行なし巨大行で全ファイルが1チャンクで返る
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 02:06'
updated_date: '2026-07-17 03:03'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 1000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
StringChunkReader.swift の advanceRespectingQuotes は引用符ごとに inQuotes をトグルし、バランスした行のみ linesConsumed を加算する。CSV 内に対応のない `"` が1つあると以降すべての行で inQuotes=true のままになり、readNextChunk が残り全ファイル(最大100MB)を1チャンクで返す。また非CSVでも行数ベースのみのため、改行なしの巨大1行ファイルは丸ごと1チャンクになる。

削除された LineChunkReader には maxChunkBytes=1MB の強制分割と、強制分割時の inQuotes リセットの両ガードがあったが、どちらも再実装されていない。巨大チャンクは ViewerStore.loadMoreLines → ViewerBridge.appendChunkScript の単一 evaluateJavaScript に流れ、UIフリーズ/メモリスパイクを起こす。

修正方向: バイト上限による強制分割(+分割時の inQuotes リセット)を StringChunkReader に再導入する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 不平衡クォートを含む巨大CSVでもチャンクサイズが上限内に収まる(テストあり)
- [x] #2 改行なしの巨大1行ファイルでもチャンクサイズが上限内に収まる(テストあり)
- [x] #3 強制分割後も後続チャンクのクォート状態が復帰し行分割が退化しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. StringChunkReader.advanceRespectingQuotes を advance(from:) に統合し、行数上限(linesPerChunk)に加えバイト上限(maxChunkBytes=1MB)を1パスの文字走査で同時に判定する。
2. バイト上限に達した場合は行境界を跨がず途中で打ち切り(forcedSplit)、resumeIndex に再開位置を保持して次回 readNextChunk がその続きから再開できるようにする。
3. forcedSplit 時は inQuotes をリセットし、対のない引用符で以降ずっと強制分割し続ける連鎖を防ぐ(削除された LineChunkReader と同じ方針)。
4. currentLine は forcedSplit の場合も含め常に advance() が返す endLine で更新し、resumeIndex が実際に属する行を正しく指すようにする(再開行のズレによる Range crash を防ぐ)。
5. TDD で AC1〜3 に対応する失敗テストを先に追加し、実装後に全テスト(340件)がパスすることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: StringChunkReader.swift の advanceRespectingQuotes を advance(from:) に置き換え、行数上限とバイト上限(1MB)を1パスで判定するよう統合。バイト上限到達時は行途中でも打ち切り、resumeIndex で再開位置を保持、inQuotes をリセットして強制分割の連鎖を防止。実装過程で「resumeIndex 再開時に scanLine の起点を stale な currentLine から取っていたため endIndex < startIndex で Range crash」というバグを検出・修正(常に advance() の返す endLine で currentLine を更新するよう修正)。

検証: StringChunkReaderTests に AC1〜3 対応の失敗テストを先に追加(不平衡クォート巨大CSV/改行なし巨大1行/強制分割後の行ベース分割復帰)。実装後 swift test --skip Integration --skip FileWatcherTests で 340 件全パスを確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
StringChunkReader にバイト上限(1MB)による強制分割を再実装し、不平衡クォートや改行なし巨大行でも1チャンクが際限なく肥大化しUIフリーズ/メモリスパイクを起こす問題を修正。強制分割時は resumeIndex で行途中から再開しつつ inQuotes をリセットし、対のない引用符による強制分割の連鎖(退化)を防止。StringChunkReaderTests に AC1〜3 を検証する3件のテストを追加し、swift test 340件全パスで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
