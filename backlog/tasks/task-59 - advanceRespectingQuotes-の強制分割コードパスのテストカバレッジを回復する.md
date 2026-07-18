---
id: TASK-59
title: advanceRespectingQuotes の強制分割コードパスのテストカバレッジを回復する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-18 08:13'
updated_date: '2026-07-18 12:06'
labels: []
dependencies:
  - TASK-57
priority: medium
type: chore
ordinal: 28000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-53 修正時に forcedSplitPreservesQuoteState テスト（1M行・6MB・respectsCSVQuotes:true）が 5K行（30KB）の軽量版に置換され、bytesScanned >= maxChunkBytes の強制分割パスを通るテストがなくなった。また既存の unbalancedQuoteLargeCSVIsChunked テストは 500 バイトクォート回復機能の導入により、チャンクが ~6KB に収まるため byte-limit アサーションが自明に成立するようになり、実質的にテストとして機能していない。
コードレビュー（arch-saguaro ブランチ、2026-07-18）で発見。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 respectsCSVQuotes:true で maxChunkBytes を超える入力に対する強制分割パスをカバーするテストが存在する
- [x] #2 unbalancedQuoteLargeCSVIsChunked が 500 バイト回復後のシナリオでも意味のあるアサーションを行う
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AC#1: respectsCSVQuotes:true でクォートフィールド内部が maxChunkBytes(1MB)境界をまたぐケースを構築し、forcedSplitPreservesQuoteStateAcrossBoundary テストとして追加。強制分割後もクォート状態(inQuotes/quotedRunLength)が保たれ、後続の複数行クォートフィールドが分断されないことを検証する。
2. AC#2: unbalancedQuoteLargeCSVIsChunked を、500バイト回復機能(TASK-57)導入後も意味のあるアサーションになるよう更新。byte-limit のみのアサーション(自明に成立)を廃し、行ベース分割への復帰を示すチャンク数(>=250、300,000行/1000行≈300)と各チャンクサイズが数KB程度に収まること(<=10000バイト)を検証する。
3. swift test 全件実行で回帰がないことを確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
forcedSplitPreservesQuoteStateAcrossBoundary を新規追加。unbalancedQuoteLargeCSVIsChunked のアサーションを byte-limit ベースから復帰検証ベースに更新。新規テストは、TASK-57修正前の実装(inQuotesを直接falseに書き換える方式)に一時的に戻しても影響を受けないこと(=byte-limit forced split パス特有のテストであること)を手動確認。既存のlongLegitimateQuotedFieldDoesNotCorruptSubsequentQuoteStateがそのバグを引き続き検出することも確認済み。swift test 全373件成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
advanceRespectingQuotes の強制分割(bytesScanned>=maxChunkBytes)コードパスをカバーする forcedSplitPreservesQuoteStateAcrossBoundary を StringChunkReaderTests.swift に追加し、クォートフィールド内部が maxChunkBytes 境界をまたぐケースで強制分割後もクォート状態が保たれ後続の複数行フィールドが破壊されないことを検証(AC#1)。unbalancedQuoteLargeCSVIsChunked のアサーションを、500バイト回復機能導入後も意味を持つよう更新し、不均衡クォート検出後に行ベース分割へ正しく復帰していること(チャンク数>=250、各チャンク<=10000バイト)を検証(AC#2)。swift test 全373件成功。
<!-- SECTION:FINAL_SUMMARY:END -->
