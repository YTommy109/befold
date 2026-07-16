---
id: TASK-15
title: 改行なし超長行の強制分割チャンクが行番号を重複させて別行として表示される
status: To Do
assignee: []
created_date: '2026-07-16 00:54'
labels: []
dependencies: []
references:
  - 'https://github.com/YTommy109/befold/issues/196'
type: bug
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
改行を含まない 1MB 超の 1 行（minified JS など）は LineChunkReader が強制分割するが、JS 側 appendChunk は継続チャンクを前行のセルへ結合せず常に新しい <tr> を追加するため、同じ行番号が繰り返される。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 _lastChunkEndedWithNewline === false の場合、最初の行分が既存最終行に結合される
- [ ] #2 行番号が重複しない
<!-- AC:END -->
