---
id: TASK-55
title: advanceByLines と advanceRespectingQuotes の行境界ロジック重複を解消する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 11:50'
updated_date: '2026-07-18 12:39'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 24000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。両メソッドが同一の行末計算・scanLine 追跡・linesConsumed カウントロジックを持っている。内部のスキャン方式（CSV のバイト単位 vs 非 CSV の行単位）と強制分割トリガーだけが異なる。変更時に 2 箇所の同期が必要。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 行境界ルックアップロジックが共通化されている
- [x] #2 既存の StringChunkReader テストがすべてパスする
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. advanceByLines と advanceRespectingQuotes の共通部分(scanLine/lineStart/linesConsumed/bytesScanned の初期化、lineEnd の O(1) 算出、linesConsumed>=linesPerChunk 判定、ループ終端時の return)を private メソッド scanLines(from:processLine:) に抽出する。
2. 行ごとの処理(バイト上限判定・強制分割・クォート追跡の有無)は差異が本質的(非CSVはO(1)行長計算、CSVはバイト単位クォート走査)なため、クロージャ(LineOutcome を返す)として各メソッド固有に残す。
3. advanceByLines / advanceRespectingQuotes をこの共通メソッドを呼ぶ薄いラッパーに書き換える。
4. 既存の StringChunkReaderTests が全てパスすることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
行境界の走査骨格(scanLine/lineStart/linesConsumed/bytesScanned の初期化・lineEnd の O(1) 算出・linesPerChunk 判定・終端 return)を private scanLines(from:processLine:) に抽出し、advanceByLines/advanceRespectingQuotes をそのクロージャ実装に置き換えた。CSV クォート追跡というアルゴリズム上の本質的差異(O(1) 行長計算 vs バイト単位クォート走査)はクロージャ内に残し、共通化しすぎて可読性を損なわないようにした。swift build 成功、swift test で StringChunkReaderTests 17件・全体373件すべて成功を確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
advanceByLines と advanceRespectingQuotes に重複していた行境界走査ロジック(scanLine 追跡・lineEnd 算出・linesConsumed カウント・ループ終端処理)を private scanLines(from:processLine:) として共通化した。行ごとの固有処理(バイト上限判定/強制分割、CSVクォート追跡)はクロージャとして各メソッドに残し、性能特性(非CSVはO(1)行長計算、CSVはバイト単位走査)を保持。swift build と swift test(StringChunkReaderTests 17件、全体373件)がすべて成功することを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
