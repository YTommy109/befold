---
id: TASK-48
title: 'StringChunkReader.advance(from:) が非 CSV ファイルでも O(bytes) スキャンする性能退行'
status: To Do
assignee: []
created_date: '2026-07-17 05:10'
updated_date: '2026-07-17 05:21'
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
- [ ] #1 非 CSV ファイルの advance(from:) がバイト単位の走査を行わない（行数ベースの O(lines) パスを使用）
- [ ] #2 10MB 程度の大規模プレーンテキストでのチャンク読込が退行前と同程度の速度であることを確認
<!-- AC:END -->
