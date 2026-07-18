---
id: TASK-58
title: ファイルサイズが maxChunkBytes と完全一致し末尾改行がないとき偽のトランケーションバナーが一瞬表示される
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-18 08:13'
updated_date: '2026-07-18 12:48'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 27000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テキスト長が maxChunkBytes (1MB) と完全一致し末尾に改行がない場合、advanceByLines/advanceRespectingQuotes が forcedSplit=true + endIndex を返す。readNextChunk は resumeIndex=endIndex かつ isAtEnd=false を設定するため、全内容を含むチャンクなのにトランケーションバナーが表示される。次の readNextChunk で空文字列 + isAtEnd=true が返り、バナーが消える。結果としてバナーが一瞬フラッシュする。
コードレビュー（arch-saguaro ブランチ、2026-07-18）で発見。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ファイルサイズが maxChunkBytes と完全一致し末尾改行がない場合にトランケーションバナーが表示されない
- [x] #2 forcedSplit=true かつ endIndex の場合を正しくハンドルするユニットテストが追加されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
readNextChunk の isAtEnd 判定を endIndex == cache.text.endIndex ベースに単純化し、forcedSplit=true でも実質的にテキスト全体を読み切っている場合を正しく isAtEnd=true として扱うよう修正(StringChunkReader.swift)。テスト exactMaxChunkBytesNoTrailingNewlineReportsAtEndImmediately を追加し最初の readNextChunk で isAtEnd=true になることを直接検証。swift test 374 tests 全て pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
readNextChunk 内の isAtEnd 判定を forcedSplit フラグ依存から endIndex==cache.text.endIndex 判定に変更し、maxChunkBytes ちょうど・末尾改行なしのケースでもトランケーションバナーが誤表示されないよう修正した。advanceByLines/advanceRespectingQuotes 側は変更不要で単純化できた。新規ユニットテストで最初の readNextChunk が isAtEnd=true を返すことを直接検証し、既存374テストも全てpass。
<!-- SECTION:FINAL_SUMMARY:END -->
