---
id: TASK-29.5
title: LineChunkReader および不要コードを削除する
status: To Do
assignee: []
created_date: '2026-07-16 12:10'
labels: []
dependencies:
  - TASK-29.3
parent_task_id: TASK-29
ordinal: 34000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
LineChunkReader.swift を削除し、TextEncoding から不要メソッド（isChunkableEncoding, trimIncompleteTail, trimIncompleteUTF8Tail）と unsupportedForChunking エラーケースを削除する。ContentLoader をバイナリ専用に簡素化する。テストの整理を含む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 LineChunkReader.swift が削除される
- [ ] #2 TextEncoding.isChunkableEncoding / trimIncompleteTail / trimIncompleteUTF8Tail が削除される
- [ ] #3 TextEncodingError.unsupportedForChunking が削除される
- [ ] #4 ContentLoader からテキストパスが削除され、バイナリ（image/pdf）専用になる
- [ ] #5 LineChunkReaderTests が削除され、TextEncodingTests が更新される
- [ ] #6 ContentLoaderTests からテキスト読み込みテストが削除される
- [ ] #7 swift build / swift test が通る
<!-- AC:END -->
