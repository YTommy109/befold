---
id: TASK-623.4
title: viewer テスト本体を TypeScript へ移す
status: To Do
assignee: []
created_date: '2026-09-14 11:58'
labels: []
dependencies:
  - TASK-623.3
parent_task_id: TASK-623
priority: medium
type: chore
ordinal: 821000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-623.3 の基盤の上で、テスト本体を `.ts` へ移し、型検査 0 件にする。背景は親 TASK-623 を参照。

2026-09-14 のスクラッチ実測（機械変換＋ハーネス型付け後、tsc 592 件）の内訳。数値は着手時に取り直すこと:

- null / undefined の可能性（`getElementById(...)` 直後の参照、`noUncheckedIndexedAccess` による添字）: 約 258 件
- 暗黙 any（テスト内ヘルパーの引数など）: 162 件
- 引数の数の不一致（TS2554）: 101 件。多くは `render` / `appendChunk` の `lang: string | undefined` を「省略」している呼び出し。テスト側で `undefined` を渡すか、本体を `lang?: string` にするかは本体の公開面に関わる判断なので、着手前に `/review-design` で決める。
- DOM 型の絞り込み（`.value` / `.dataset` など）: 32 件
- 契約外の値を意図して渡す防御テスト・不完全な fixture（`DiffLine` など）: 10 件
- jsdom の `DOMWindow` と DOM 型の不一致: 2 件

oxlint の `no-unsafe-*` はテストでプロジェクトレベル off のまま（2026-09-14 実測で TS 化後も約 570 件残る）。再有効化は本タスクの範囲外で、件数だけを記録する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer のテストファイルに `.js` が残っていない（`support/` を含む）
- [ ] #2 テスト用の型検査が 0 件で通る
- [ ] #3 契約外の入力を意図して渡すテストは、型エラーを `@ts-expect-error` など意図が読める形で明示している
- [ ] #4 Jest のテスト件数が移行前から減っていない
- [ ] #5 `.claude/CLAUDE.md` と `BefoldApp/.oxlintrc.json` のテスト由来 `no-unsafe-*` 件数・本数の記述が実測値に更新されている
<!-- AC:END -->
