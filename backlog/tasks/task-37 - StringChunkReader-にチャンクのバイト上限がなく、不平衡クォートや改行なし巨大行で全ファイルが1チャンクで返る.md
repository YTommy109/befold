---
id: TASK-37
title: StringChunkReader にチャンクのバイト上限がなく、不平衡クォートや改行なし巨大行で全ファイルが1チャンクで返る
status: To Do
assignee: []
created_date: '2026-07-17 02:06'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 20000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
StringChunkReader.swift の advanceRespectingQuotes は引用符ごとに inQuotes をトグルし、バランスした行のみ linesConsumed を加算する。CSV 内に対応のない `"` が1つあると以降すべての行で inQuotes=true のままになり、readNextChunk が残り全ファイル(最大100MB)を1チャンクで返す。また非CSVでも行数ベースのみのため、改行なしの巨大1行ファイルは丸ごと1チャンクになる。

削除された LineChunkReader には maxChunkBytes=1MB の強制分割と、強制分割時の inQuotes リセットの両ガードがあったが、どちらも再実装されていない。巨大チャンクは ViewerStore.loadMoreLines → ViewerBridge.appendChunkScript の単一 evaluateJavaScript に流れ、UIフリーズ/メモリスパイクを起こす。

修正方向: バイト上限による強制分割(+分割時の inQuotes リセット)を StringChunkReader に再導入する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 不平衡クォートを含む巨大CSVでもチャンクサイズが上限内に収まる(テストあり)
- [ ] #2 改行なしの巨大1行ファイルでもチャンクサイズが上限内に収まる(テストあり)
- [ ] #3 強制分割後も後続チャンクのクォート状態が復帰し行分割が退化しない
<!-- AC:END -->
