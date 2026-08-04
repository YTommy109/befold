---
id: TASK-29.5
title: LineChunkReader および不要コードを削除する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 12:10'
updated_date: '2026-07-16 12:54'
labels: []
dependencies:
  - TASK-29.3
parent_task_id: TASK-29
priority: high
ordinal: 6
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LineChunkReader.swift を削除し、TextEncoding から不要メソッド（isChunkableEncoding, trimIncompleteTail, trimIncompleteUTF8Tail）と unsupportedForChunking エラーケースを削除する。ContentLoader をバイナリ専用に簡素化する。テストの整理を含む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LineChunkReader.swift が削除される
- [x] #2 TextEncoding.isChunkableEncoding / trimIncompleteTail / trimIncompleteUTF8Tail が削除される
- [x] #3 TextEncodingError.unsupportedForChunking が削除される
- [x] #4 ContentLoader からテキストパスが削除され、バイナリ（image/pdf）専用になる
- [x] #5 LineChunkReaderTests が削除され、TextEncodingTests が更新される
- [x] #6 ContentLoaderTests からテキスト読み込みテストが削除される
- [x] #7 swift build / swift test が通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
LineChunkReader.swift 削除、ChunkedTextReading プロトコルは StringChunkReader.swift へ移設。TextEncoding から isChunkableEncoding/trimIncompleteTail/trimIncompleteUTF8Tail と TextEncodingError.unsupportedForChunking を削除。ContentLoader.load をバイナリ専用(image/pdf)に簡素化(text 分岐・isBinary 判定・readString 呼び出しを削除、既に ViewerStore からは isBinaryContent==true でのみ呼ばれていたため実質デッドコードだった)。LineChunkReaderTests.swift を削除し、埋め込まれていた TextEncodingTests suite(detectBOM 系のみ)を befoldTests/TextEncodingTests.swift として独立ファイル化。ContentLoaderTests のテキスト読み込みテストを削除し、バイナリ専用の oversizedFileIsRejected(image, maxFileSizeBytes)/readFailureIsRejected に置き換え。ViewerStoreTests の紛らわしいテスト名(LineChunkReader 言及)も実態(チャンク読み込み一般)に合わせて修正。xcodegen generate で befold.xcodeproj を再生成。swift build / swift test --skip Integration --skip FileWatcherTests: 333 tests in 43 suites すべて pass。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
LineChunkReader.swift と関連の不要コード(TextEncoding の isChunkableEncoding/trimIncompleteTail/trimIncompleteUTF8Tail、TextEncodingError.unsupportedForChunking)を削除し、ContentLoader をバイナリ(image/pdf)専用に簡素化した。ChunkedTextReading プロトコルは StringChunkReader.swift へ移設して存続。テストは LineChunkReaderTests.swift を削除し、埋め込まれていた TextEncodingTests を独立ファイル化、ContentLoaderTests・ViewerStoreTests のテキスト読込関連/紛らわしい記述を整理。swift build 成功、swift test で 333 tests 全 pass を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
