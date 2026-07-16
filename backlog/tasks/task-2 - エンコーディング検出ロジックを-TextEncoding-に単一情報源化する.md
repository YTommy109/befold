---
id: TASK-2
title: エンコーディング検出ロジックを TextEncoding に単一情報源化する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 00:39'
updated_date: '2026-07-16 06:56'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/202
priority: low
ordinal: 7000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #202 から移行。3つの重複: (1) decodeText が detectEncoding の検出ロジックを再実装、(2) NUL パリティ計数が FileReading と TextEncoding に同一内容でインライン展開、(3) 先頭スニフ窓 8192 バイトが binarySniffLength と sniffLength の 2 定数に分裂。片側だけ変更すると全量読みとチャンク読みが静かに乖離するリスク。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 decodeText が detectEncoding に委譲している
- [x] #2 NUL パリティ計数の共有ヘルパーが TextEncoding に一箇所で定義されている
- [x] #3 先頭スニフ窓の定数が単一情報源になっている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. TextEncoding.detectEncoding にBOMなしNULヒューリスティック(UTF-16判定)を追加し、その後にdecodeTextをdetectEncoding委譲+BOM剥がしのみに簡略化する(AC1)。LineChunkReaderのisChunkableEncodingが既にBOMなし+NUL混入を弾くため挙動は変わらない。
2. TextEncoding.nulParity(_:) -> (even: Int, odd: Int) を追加し、looksLittleEndianUTF16とDefaultFileReader.looksLikeUTF16の計数ループをこれに置き換える(AC2)。閾値判定ロジックはそれぞれの呼び出し元に残す。
3. DefaultFileReader.binarySniffLength を削除しTextEncoding.sniffLengthを直接参照する(AC3)。
4. swift test で既存テスト(TextEncodingTests, LineChunkReaderTests, DefaultFileReaderTests)が通ることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
detectEncoding にNULヒューリスティックを移設しdecodeTextはBOM剥がし+detectEncoding委譲に簡略化(AC1)。TextEncoding.nulParity(_:)を追加しlooksLittleEndianUTF16/DefaultFileReader.looksLikeUTF16の計数ループを共通化(AC2)。DefaultFileReader.binarySniffLengthを削除しTextEncoding.sniffLengthを直接参照(AC3)。swift test --skip Integration --skip FileWatcherTests: 323 tests passed(全suite green)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TextEncoding.detectEncoding にBOMなしUTF-16のNULヒューリスティックを追加し、decodeTextはBOM剥がしのみ残してdetectEncoding委譲に簡略化(AC1)。TextEncoding.nulParity(_:)を新設し、looksLittleEndianUTF16とDefaultFileReader.looksLikeUTF16の重複していたNULカウントループを置き換え(AC2)。DefaultFileReader.binarySniffLengthを削除しTextEncoding.sniffLengthに一本化(AC3)。LineChunkReaderのisChunkableEncodingが既にBOMなし+NUL混入を弾くためチャンク読み込み経路の挙動に変化なし。swift test --skip Integration --skip FileWatcherTests で323件全テスト成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
