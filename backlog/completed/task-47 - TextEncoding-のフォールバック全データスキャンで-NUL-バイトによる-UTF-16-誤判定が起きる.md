---
id: TASK-47
title: TextEncoding のフォールバック全データスキャンで NUL バイトによる UTF-16 誤判定が起きる
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-17 05:10'
updated_date: '2026-07-17 08:04'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 3000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
detectAndDecodeText のフォールバックパスがファイル全体を sniffWindow として渡すため、8KB 以降に NUL バイトを含む Shift_JIS ファイル等が UTF-16 と誤分類される。また detectEncoding (公開 API) にはこのフォールバック自体がなく、2つの検出エントリポイント間でロバスト性が不一致。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォールバック時の NUL バイトチェックが全ファイルではなく適切な範囲に限定される
- [x] #2 detectEncoding と detectAndDecodeText の両公開 API が同一のフォールバック戦略を共有する
- [x] #3 先頭 8KB が ASCII で本文に NUL を含む Shift_JIS ファイルが正しく処理されることをテストで確認
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. detectEncodingAndDecode の NUL 判定窓を sniffWindow 引数から分離し、常に data.prefix(sniffLength) に限定する(フォールバック時に sniffWindow=全データが渡っても NUL 判定は先頭 8KB に留める)。
2. detectEncoding に detectAndDecodeText と同型の「先頭 sniffLength バイトで判定→失敗時のみ全データで再試行」フォールバックを追加する(detectWithFallback として共通化)。
3. detectAndDecodeText 側は復号成否まで含めた既存の2段階リトライ(decodeUsingDetection)を維持しつつ、内部の detectEncodingAndDecode は修正版を使う。
4. 先頭8KBがASCIIで本文にNULを含むShift_JISファイルのテストを追加し、decodeText と detectEncoding の両方で誤判定しないことを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 実行(350 tests, 45 suites)全て成功。TextEncodingTests に task-47 用の回帰テストを2件追加(decodeText / detectEncoding)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
detectEncodingAndDecode の NUL バイト判定を常に先頭 sniffLength(8KB)に限定し、フォールバック時(sniffWindow=全データ)でも全文スキャンしないよう修正。あわせて detectEncoding にも detectAndDecodeText と同型の2段階フォールバック(先頭8KB→失敗時のみ全データ)を追加し、両公開APIの判定戦略を一致させた。先頭8KBがASCIIで本文にNULを含むShift_JISファイルのテストを追加し、swift test (350 tests) で全件成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
