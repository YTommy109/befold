---
id: TASK-485.12
title: 変更ブロックジャンプの highlight 処理を効率化し、移動・ハイライトを find と共通化する
status: To Do
assignee: []
created_date: '2026-08-17 14:04'
labels: []
dependencies: []
parent_task_id: TASK-485
priority: medium
type: enhancement
ordinal: 746000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘 3 件、verdict: いずれも CONFIRMED）

いずれもジャンプバーの移動・ハイライト実装（`viewer-src/jump.ts` / `jump-providers.ts`）に集中しており、1 つの PR で直せるためまとめて起票する。

### 1. collectChangeBlocks が O(k²)

`viewer-src/jump-providers.ts:95` が行ごとに `previous.highlight = previous.highlight.concat(edge)` で配列を作り直すため、ブロック列挙がブロックサイズ k に対して O(k²)。GitDiffReader は `wholeFileContextLines = 1_000_000`（`GitDiffReader.swift:26/89`）なので、全面書き換えの 5,000 行ファイルは del+add 約 10,000 行の単一ブロックになり、ジャンプバーを開く・再構築するたびに約 5,000 万要素コピーが走る。`push(...edge)`（または単一セルの push）で O(k) にできる。

### 2. clearCurrent が毎キー入力で全 target を走査

`viewer-src/jump.ts:68` の clearCurrent は、1 つの target しか持たないクラスを外すために全 target の highlight 要素を走査する。changeBlock プロバイダでは highlight 配列の合計が変更行ごとに 1 セルなので、Enter / Shift+Enter のたびに O(全変更行) の classList 操作（大きい差分で数万件）になる。現在 target を覚えてその要素だけ外す。

### 3. moveTo / highlightCurrent / scrollIntoView の find との重複

`find.ts:322-335` と `jump.ts:139-153` が `scrollIntoView({block:"center",behavior:"smooth"})` を含む同形の実装を重複して持つ。UX 上の決定なので `navigation.ts` に一本化し、2 つのバーが黙って乖離しないようにする。

性能の主張（5,000 万コピー等）は静的算出であり実測はしていない。体感差の主張が必要なら fixed-cadence ではなくレイテンシで測ること（memory: fixed-cadence-perf-measurement-inverts）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブロック列挙が O(k)（行ごとの配列コピーが無い）
- [ ] #2 clearCurrent が現在 target の要素だけを操作する
- [ ] #3 スクロール・現在位置ハイライトの実装が navigation.ts の 1 箇所にあり、find と jump の挙動が変わらない
- [ ] #4 既存の jest テストが通る（挙動不変の確認）
<!-- AC:END -->
