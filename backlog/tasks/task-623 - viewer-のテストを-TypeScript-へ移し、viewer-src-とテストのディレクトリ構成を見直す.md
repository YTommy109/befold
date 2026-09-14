---
id: TASK-623
title: viewer のテストを TypeScript へ移し、viewer-src とテストのディレクトリ構成を見直す
status: To Do
assignee: []
created_date: '2026-09-14 11:56'
updated_date: '2026-09-14 11:57'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 817000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
viewer の本体（`BefoldApp/viewer-src/`）は TASK-499 で全モジュール TypeScript になったが、Jest テストは `BefoldApp/BefoldKit/Resources/__tests__/*.test.js`（16 本 + `support/` 2 本、計 6,883 行。2026-09-14 実測）と JavaScript のまま残っている。

## なぜ直すか

- babel-jest は型注釈を落とすだけなので、本体の関数シグネチャを変えてもテストは黙って通る。2026-09-14 にスクラッチでテストを `.ts` 化して `tsc --noEmit` をかけると 592 件出て、うち 101 件（TS2554）は `render(content, type, lang)` の第 3 引数をテストが省略している箇所だった。型でテストの呼び方を検出できていない。
- テストが `BefoldKit/Resources/__tests__` にあるのは、テスト対象の `viewer.js` が Resources にあった頃（128b4e53, #51）の名残。TASK-432.2 でソースを `viewer-src/` へ移した際にテストだけ残り、移設の検討記録は無い。この置き場所のために `Package.swift` の `exclude: ["Resources/__tests__"]` と `project.yml` の `excludes: "__tests__/**"` が要っている。
- `viewer-src/` は 37 ファイルがフラットに並んでいる（find / jump / bar / csv / diff / render などの関心が同じ階層に混在）。テストの置き場所を決め直すなら、ソース側の構成も同時に見直さないと二度手間になる。

## 経緯・調査の出典

2026-09-14 のセッションで、PR #652（検索ハイライトの高速化）のマージ前に「バンドルをコミットしている理由」「テストも TS 側に移すべきでは」という問いから調査した。実測に使ったスクラッチ（機械変換した 16 本で Jest 644 件パス、tsc 592 件）はセッション限りで残っていないため、数値は着手時に取り直すこと。

## 着手前に知っておくこと（2026-09-14 時点の実測）

- テストが読むのは成果物 `viewer-bundle.js` ではなくソース。8 本は babel-jest で `viewer-src/main` を直接 require、残りは `support/viewerMainHarness.js` が esbuild でその場でバンドルして jsdom の `window.eval` で評価する（babel 経由にしない理由は TASK-432.2 の Notes）。
- ハーネス経由の `main` は `@types/jsdom` の `DOMWindow` から取り出すため完全に any。型を付けない限り、ハーネス系テストでは TS 化の効果がほぼ出ない。
- 本体の `tsconfig.json` は `types: []`・DOM のみで Node 型を意図して外している。テストを `viewer-src/` 配下に置くと、この tsconfig と `.oxlintrc.json` の `viewer-src/**` override（`no-unsafe-*` を error）がテストにもかかる。
- テスト本体に `jest.spyOn` / `jest.fn` / `jest.mock` はほぼ無い（PR #652 で `jest.spyOn` が 1 件入った）。
- `.claude/CLAUDE.md` と `BefoldApp/.oxlintrc.json` は「`__tests__` の 9 本」と書いているが実数は 16 本で、文書が古い。
- 関連 ADR: `docs/adr/0005-bundle-viewer-js-with-esbuild.md`（バンドルのコミット方針。本タスクでは変えない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer のテストがすべて TypeScript で書かれ、型検査（`tsc`）が CI で 0 件を要求している
- [ ] #2 `viewer-src` とテストのディレクトリ構成が、決めた方針とその理由の記録どおりになっている
- [ ] #3 `BefoldKit/Resources/` 配下にテストが残っておらず、`Package.swift` / `project.yml` にテスト除外のための指定が残っていない
- [ ] #4 Jest のテスト件数が移行前から減っていない
<!-- AC:END -->
