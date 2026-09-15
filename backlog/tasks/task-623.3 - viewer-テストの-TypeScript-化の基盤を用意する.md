---
id: TASK-623.3
title: viewer テストの TypeScript 化の基盤を用意する
status: Done
assignee:
  - '@claude'
created_date: '2026-09-14 11:58'
updated_date: '2026-09-15 02:03'
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
- [x] #1 テスト用の型検査コマンドがあり、CI の js-test ジョブで実行されている
- [x] #2 テストハーネスと support が TypeScript になり、ハーネスが返す公開面に型が付いている（存在しない関数の呼び出しが型エラーになる）
- [x] #3 Jest が `.ts` のテストを実行でき、既存のテスト件数が減っていない
- [x] #4 本体の `tsconfig.json` の型設定（`types: []`・DOM のみ）がテスト都合で緩んでいない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 型の依存を足す: @jest/globals（jest と同版で型が付く。@types/jest は入れない）、@types/jsdom 21.1.7（jsdom 25 向けの版が無く、27 未満の最新）、@types/node（推移依存に頼らない）
2. viewer-test/tsconfig.json を新設（../tsconfig.json を extends、lib ES2023 + DOM、types [node]、viewer-globals.d.ts を include）
3. support/ の 2 本を .ts へ。ハーネスの戻り値 main に typeof import(main) を付ける
4. package.json: typecheck:viewer-test、jest の testMatch を .js/.ts 両対応、setupFiles を .ts へ
5. CI js-test に typecheck:viewer-test を足す
6. 検証: tsc 0 件、存在しない関数呼び出しが TS2339 になるプローブ、Jest 645 件、lint / format / bundle
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（2026-09-15）:
- `npm run typecheck:viewer-test` exit 0。`tsc -p viewer-test --listFilesOnly` で viewer-src 34 本 + viewer-test 2 本（support の .ts）が検査対象。本体 viewer-src を node 型込みで検査しても 0 件だった
- プローブ（`loaded.main.noSuchFunction(1,2,3)` と `loaded.main.render('a','markdown')`）で TS2339 と TS2554 が出ることを確認し、プローブは削除
- Jest 16 suites / 645 tests（変更前と同数）。babel.config.cjs は変更なしで .ts のハーネス / setupFiles を実行できた
- `git diff origin/main -- BefoldApp/tsconfig.json` は空（本体の types: [] / DOM のみを維持）
- 想定外: ハーネスに型が付いたことで oxlint --type-aware が .js のテストでも戻り値型を追えるようになり、新たに 5 件鳴った（no-floating-promises 3: mermaid が jsdom で解決しないため意図して待たない render / strict-void-return 1: 式本体の forEach / unbound-method 1: DOMTokenList.prototype.remove の退避）。前 2 種は void とブロック本体で意図を明示、unbound-method は理由つきの disable コメントにした
- `npm run lint` / `format:check` / `check:viewer-bundle` / `check:third-party-licenses` いずれも exit 0
- viewer-src/README.md のコマンド一覧に残っていた存在しない `npm run lint:viewer`（ESLint 時代の名残）を `npm run lint` に直した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-test/tsconfig.json（本体を extends、node 型と ES2023 lib を追加）と npm run typecheck:viewer-test を足し、CI js-test で実行するようにした。support/ の 2 本を .ts にし、ハーネスの main に barrel の型を付けた（存在しない関数呼び出しが TS2339 になることをプローブで確認）。Jest 645 件は変わらず、本体 tsconfig は無変更。
<!-- SECTION:FINAL_SUMMARY:END -->
