---
id: TASK-48
title: 'StringChunkReader.advance(from:) が非 CSV ファイルでも O(bytes) スキャンする性能退行'
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 05:10'
updated_date: '2026-07-17 07:36'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 2000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
advance(from:) は respectsCSVQuotes=false でも全バイトを走査する。旧コードは O(1) の行番号計算パスを持っていた。非 CSV ファイルでは linesPerChunk=1000 が先に到達するため、バイトスキャンは無駄。行単位の distance 計算で十分で、バイトスキャンは maxChunkBytes 境界を跨ぐ行だけに限定すべき。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 非 CSV ファイルの advance(from:) がバイト単位の走査を行わない（行数ベースの O(lines) パスを使用）
- [x] #2 10MB 程度の大規模プレーンテキストでのチャンク読込が退行前と同程度の速度であることを確認
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. advance(from:) を respectsCSVQuotes で分岐: advanceByLines(非CSV, 行単位のO(1)境界参照+行境界distanceでバイト予算管理) と advanceRespectingQuotes(既存のバイト単位クォート走査) に分離。
2. advanceByLines は各行を lineStartIndices から O(1) 参照し、maxChunkBytes を跨ぐ行でのみ index(offsetBy:) で強制分割位置を計算(バイト単位の逐次スキャンをしない)。
3. 既存テスト(12件)全パス確認 + 10MB平文ベンチで旧実装(0.114s)→新実装(0.021s)の高速化を確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
advance(from:) を advanceByLines(非CSV)/advanceRespectingQuotes(CSV) に分割。非CSVパスは lineStartIndices を使った O(1) 行境界参照とし、バイト走査は maxChunkBytes 境界を跨ぐ行の強制分割時のみ行う。swift test 全361件パス。10MB平文ベンチ(一時テストで計測後削除): 旧実装 0.114s → 新実装 0.021s (約5.5倍高速化)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
advance(from:) を respectsCSVQuotes で advanceByLines/advanceRespectingQuotes に分岐。非CSVパスは lineStartIndices 参照による O(1) 行境界計算に戻し、バイト単位走査は maxChunkBytes を跨ぐ行の強制分割時のみに限定。既存テスト(swift test, 361件)全パス、10MB平文ベンチで旧実装比約5.5倍高速化(0.114s→0.021s)を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
