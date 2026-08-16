---
id: TASK-499
title: viewer-src の残り 22 本の JS を TypeScript へ移行しきる
status: To Do
assignee: []
created_date: '2026-08-16 07:20'
updated_date: '2026-08-16 07:20'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 735000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-432.4 で viewer の JS→TS 段階移行を始めたが、移行できたのはブリッジ契約に関わる 4 本（`bridge.ts` / `expose.ts` / `fonts.ts` / `truncation.ts`）だけで、`viewer-src/` には **.js が 22 本・約 3,000 行残っている**（2026-08-16 実測、総行数 3,370 のうち .ts は 202 行）。

`BefoldApp/tsconfig.json:29-30` が `allowJs: true, checkJs: false` なので、残る .js は **tsc の型検査を一切受けていない**。大きいものは `find.js`(464) / `zoom.js`(327) / `diff-html.js`(277) / `render.js`(264) / `path-refs.js`(249) / `code-html.js`(223) / `csv-html.js`(210) / `renderers.js`(201)。

## なぜ今これを起票するか

<!-- blocked-by ./task-498 - Oxlint-Oxfmt-を導入して-LLM-生成コードの品質を機械で守る.md -->

TASK-498 で Oxlint を入れるにあたり、**viewer-src だけ緩めの設定にする**判断をした。型情報の無い .js に対して型前提の厳しいルールを当てると指摘が大量に出るうえ、その多くは「TS へ移せば消えるもの」で、個別に無効化コメントを積むのは無駄になるため。

つまり viewer-src の緩和は TS 移行が終わるまでの暫定措置であり、**このタスクが終わらないと Oxlint の厳しさが site/ と揃わない**。緩和を撤去するところまでがこのタスクの範囲。

## 注意

- テストは `BefoldApp/BefoldKit/Resources/__tests__/` にあり、`require('../../../viewer-src/main.js')` の形で viewer-src を直接読んでいる。拡張子を変えると require のパスが壊れる（jest の `moduleNameMapper` は `^(\.{1,2}/.*)\.js$` → `$1` で拡張子を剥がすので、テスト側の記述も合わせて確認する）。
- `support/viewerMainHarness.js` は esbuild をその場で呼んでバンドルし JSDOM に流す。移行中もこの経路が壊れないことを都度確認する。
- `viewer-bundle.js` はコミットされた成果物で、CI の `check:viewer-bundle` がソースとのズレを検出する。移行のたびに再生成が要る。
- 一度に全部移さない。ファイル単位で移せる構成（`allowJs`）になっているので、依存の浅いものから順に移して各段階でテストを通す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 viewer-src から .js が無くなり、全モジュールが .ts になっている
- [ ] #2 BefoldApp/tsconfig.json の allowJs / checkJs 設定が移行完了に合わせて見直されている
- [ ] #3 Oxlint の viewer-src 向け緩和（TASK-498 で入れた override）が撤去され、site/ と同じ厳しさの設定が適用されている
- [ ] #4 既存の jest テストが通り、ケース数が減っていない
- [ ] #5 check:viewer-bundle が通る（バンドル成果物とソースがずれていない）
<!-- AC:END -->
