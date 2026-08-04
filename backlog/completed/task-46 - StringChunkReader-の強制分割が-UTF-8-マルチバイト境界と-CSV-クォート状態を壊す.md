---
id: TASK-46
title: StringChunkReader の強制分割が UTF-8 マルチバイト境界と CSV クォート状態を壊す
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 05:09'
updated_date: '2026-07-17 07:47'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 2100
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
maxChunkBytes での強制分割時に2つの問題がある: (1) utf8View.index(after:) でバイト単位に進めるため UTF-8 継続バイト上で分割しうる（旧コードは行境界分割で文字境界を保証していた）。(2) 分割後に inQuotes が無条件に false にリセットされ、クォート内の複数行 CSV フィールドが正しくチャンクされない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 強制分割が UTF-8 文字境界を尊重し、マルチバイト文字の途中で分割しない
- [x] #2 強制分割後も inQuotes 状態が維持され、クォート内複数行フィールドが正しくチャンクされる
- [x] #3 1MB超の単一行日本語テキストでの強制分割テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. StringChunkReader.advanceByLines の強制分割位置(utf8View.index(offsetBy:))をUTF-8スカラー境界にスナップするヘルパーを追加し適用する\n2. advanceRespectingQuotes の強制分割位置(cursor)にも同じヘルパーを適用する\n3. readNextChunk の forcedSplit 後の inQuotes=false リセットを削除し、実際の状態を維持する\n4. 既存テスト forcedSplitRecoversLineBasedChunking はリセット挙動を前提にしているため、inQuotes 維持後の正しい挙動(不平衡クォートなら以降ずっと inQuotes=true でバイト上限のみで区切られる)に合わせて更新する\n5. AC#3 用に 1MB 超の単一行日本語(マルチバイト)テキストの強制分割テストを追加する\n6. swift test で全テスト確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
advanceByLines/advanceRespectingQuotes の強制分割終端に snappedToCharacterBoundary を追加し、UTF-8継続バイト上での分割を後退補正。readNextChunk の inQuotes=false リセットを削除し、実際のクォート状態を維持。既存テスト forcedSplitRecoversLineBasedChunking はリセット前提だったため forcedSplitPreservesQuoteState に更新(inQuotes維持なら不平衡クォート時は行ベースへ退化しないことを検証)。AC#3向けに forcedSplitRespectsMultibyteCharacterBoundary を追加(1MB超の「あ」のみの単一行、各チャンクのUTF-8バイト数が3の倍数であることを検証)。swift test --skip Integration --skip FileWatcherTests で348件全パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
StringChunkReader の強制分割で(1)UTF-8マルチバイト境界を尊重するようスナップ処理を追加し、(2)分割後もinQuotes状態を維持するよう修正した。既存テストを新挙動に合わせて更新し、1MB超日本語単一行の境界テストを追加。swift test 348件全パスで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
