---
id: TASK-485.12
title: 変更ブロックジャンプの highlight 処理を効率化し、移動・ハイライトを find と共通化する
status: Done
assignee: []
created_date: '2026-08-17 14:04'
updated_date: '2026-08-18 04:24'
labels: []
milestone: m-6
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
- [x] #1 ブロック列挙が O(k)（行ごとの配列コピーが無い）
- [x] #2 clearCurrent が現在 target の要素だけを操作する
- [x] #3 スクロール・現在位置ハイライトの実装が navigation.ts の 1 箇所にあり、find と jump の挙動が変わらない
- [x] #4 既存の jest テストが通る（挙動不変の確認）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: (1) collectChangeBlocks は concat をやめ highlight.push(...edge) で伸ばす（ブロック行数 k に対し O(k)）。(2) jump.ts は現在位置の印が付いている要素を currentHighlight として覚え、clearCurrent はその要素だけを操作する（列の全走査を廃止）。invalidate では currentHighlight も捨てる。find.ts も同形にした（従来は全マッチを走査していた）。(3) 印の付け替えとスクロール（block:center / smooth）を navigation.ts の moveCurrentHighlight に集約し、find.highlightCurrent と jump.highlightCurrent の双方がそこを通る。

担保: viewer-main-jump.test.js に「移動時に外す印は直前のブロックの分だけ」を追加（20 行 x 2 ブロックで next 時の remove('mmd-jump-current') 呼び出しが 20 回）。全走査へ戻すと 40 回で落ちることを、実際に jump.ts を全走査版へ書き換えて再ビルドし確認済み（Expected 20 / Received 40）。

検証: npx tsc --noEmit（No errors found）、npm run lint（--type-aware、指摘なし）、npm run format:check（All matched files use the correct format）、npm test（10 suites / 520 tests all passed）。性能の主張は静的算出のままで、レイテンシ実測は行っていない。

docs/dev/native-app-design.md は更新不要と判断した（挙動不変の内部実装の変更で、現在仕様として記述している内容に変化がないため）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
変更ブロック列挙の O(k^2) を解消し、現在位置ハイライトの解除を直前要素のみに限定し、スクロール・現在位置ハイライトを navigation.ts の moveCurrentHighlight へ一本化した（find/jump 共通）。tsc / lint / format:check / jest 520 件で検証し、追加した回帰テストが旧実装で落ちることも確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
