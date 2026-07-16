---
id: TASK-29.3
title: StringChunkReader を実装する
status: To Do
assignee: []
created_date: '2026-07-16 12:10'
updated_date: '2026-07-16 12:10'
labels: []
dependencies:
  - TASK-29.2
references:
  - docs/superpowers/plans/2026-07-16-normalized-text-cache.md
parent_task_id: TASK-29
ordinal: 32000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
NormalizedTextCache から行インデックスベースで String スライスを返す actor を新規追加する。ChunkedTextReading プロトコルを実装し、LineChunkReader を置き換える。I/O なし・デコードなし・例外なしの純粋な文字列操作。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 StringChunkReader が ChunkedTextReading プロトコルを実装する
- [ ] #2 linesPerChunk (1000行) ごとの String スライスを返す
- [ ] #3 CSV の引用符内改行を正しく扱う（respectsCSVQuotes オプション）
- [ ] #4 最終チャンクで isAtEnd = true を返す
- [ ] #5 空キャッシュに対して初回で isAtEnd = true を返す
- [ ] #6 テスト: 基本チャンク分割、CSV 引用符、1000 行未満ファイル、空ファイル
<!-- AC:END -->
