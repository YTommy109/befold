---
id: TASK-56
title: TextEncodingTests の Shift_JIS テストデータ構築コピペを共通ヘルパーに整理する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-17 11:50'
updated_date: '2026-07-18 12:42'
labels: []
dependencies: []
modified_files:
  - BefoldApp/befoldTests/TextEncodingTests.swift
priority: low
type: chore
ordinal: 25000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コードレビューで発見。3 つの連続テストが同一の Shift_JIS テストデータ（8KB+ ASCII ヘッダー）をコピペで構築している。共通ヘルパー関数で整理すればテスト意図が明確になり、エッジケース追加時のボイラープレートも不要になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 テストデータ構築が共通ヘルパーに集約されている
- [x] #2 既存テストの検証内容が変わっていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. asciiHeader(sniffLength+1000) + body から text/data を組み立てる共通ヘルパー関数を TextEncodingTests に追加する
2. decodesShiftJISWithAsciiHeaderExceedingSniffLength / decodesShiftJISWithNulByteAfterAsciiHeader / detectEncodingDoesNotMisdetectShiftJISWithNulByteAsUtf16 の3テストをヘルパー利用に置き換える(検証内容は変更しない)
3. swift test で対象テストの green を確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
asciiHeader(sniffLength+1000)+body組み立てをmakeShiftJISDataWithAsciiHeader(body:)に共通化し、3テストで利用。swift test --filter TextEncodingTests で10件green確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TextEncodingTests の Shift_JIS テストデータ構築を共通ヘルパー makeShiftJISDataWithAsciiHeader(body:) に集約。3テストの検証内容は変更なし。swift test --filter TextEncodingTests で全10件passを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
