---
id: TASK-623.3
title: viewer テストの TypeScript 化の基盤を用意する
status: To Do
assignee: []
created_date: '2026-09-14 11:58'
labels: []
dependencies:
  - TASK-623.2
parent_task_id: TASK-623
priority: medium
type: chore
ordinal: 820000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
テスト本体を `.ts` にする前に、型検査とテスト実行の土台を整える。背景は親 TASK-623 を参照。

2026-09-14 時点の実測で分かっていること（着手時に裏を取ること）:

- 本体の `tsconfig.json` は `types: []`・DOM のみで Node 型を意図して外しているため、テストは別の tsconfig（本体を extends する等）が要る。テストは `toSorted` を使っており、`lib` が ES2022 のままだと TS2550 になる。
- `@types/jest` と `@types/jsdom` は `node_modules/@types` に無い。`@types/node` は推移依存で入っている。
- babel-jest（`babel.config.cjs` の preset-typescript）は変更なしで `.ts` のテストを実行できた（Jest の `testMatch` と `setupFiles` の変更だけで 644 件パス）。
- `support/viewerMainHarness.js` が返す `main` は jsdom の `DOMWindow` 経由で完全に any。ここに `typeof import(main)` 相当の型を付けないと、ハーネス経由のテストは型検査の対象にならない（実測: `loaded.main.noSuchFunction(1,2,3)` が tsc を通った）。
- `scripts/oxc-lint.sh` は既に `.ts` を拾う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テスト用の型検査コマンドがあり、CI の js-test ジョブで実行されている
- [ ] #2 テストハーネスと support が TypeScript になり、ハーネスが返す公開面に型が付いている（存在しない関数の呼び出しが型エラーになる）
- [ ] #3 Jest が `.ts` のテストを実行でき、既存のテスト件数が減っていない
- [ ] #4 本体の `tsconfig.json` の型設定（`types: []`・DOM のみ）がテスト都合で緩んでいない
<!-- AC:END -->
