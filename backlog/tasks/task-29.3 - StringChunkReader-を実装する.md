---
id: TASK-29.3
title: StringChunkReader を実装する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-16 12:10'
updated_date: '2026-07-16 12:35'
labels: []
dependencies:
  - TASK-29.2
references:
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
parent_task_id: TASK-29
priority: high
ordinal: 4
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NormalizedTextCache から行インデックスベースで String スライスを返す actor を新規追加する。ChunkedTextReading プロトコルを実装し、LineChunkReader を置き換える。I/O なし・デコードなし・例外なしの純粋な文字列操作。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 StringChunkReader が ChunkedTextReading プロトコルを実装する
- [x] #2 linesPerChunk (1000行) ごとの String スライスを返す
- [x] #3 CSV の引用符内改行を正しく扱う（respectsCSVQuotes オプション）
- [x] #4 最終チャンクで isAtEnd = true を返す
- [x] #5 空キャッシュに対して初回で isAtEnd = true を返す
- [x] #6 テスト: 基本チャンク分割、CSV 引用符、1000 行未満ファイル、空ファイル
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
TDD で実装（実装計画 Task 2 に準拠）:
1. テストファイル StringChunkReaderTests.swift を作成
2. コンパイルエラーで失敗することを確認
3. StringChunkReader.swift を実装
4. テストが全て通ることを確認
5. コミット
<!-- SECTION:PLAN:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
StringChunkReader を BefoldKit に追加。9 テスト全合格（swift test --filter StringChunkReaderTests）。全 352 テスト合格を確認。ChunkedTextReading プロトコル準拠、1000 行チャンク分割、CSV 引用符対応、空キャッシュ・末尾改行なし・読了後再呼び出しをテストでカバー。
<!-- SECTION:FINAL_SUMMARY:END -->
