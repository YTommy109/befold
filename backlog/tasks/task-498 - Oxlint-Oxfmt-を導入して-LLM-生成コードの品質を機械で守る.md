---
id: TASK-498
title: Oxlint / Oxfmt を導入して LLM 生成コードの品質を機械で守る
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-16 07:19'
updated_date: '2026-08-16 07:35'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 734000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
JS/TS 側には lint がほぼ無く、フォーマッタは 1 つも無い。LLM が書いたコードを機械で受け止める層が Swift 側（swiftformat / swiftlint）にしか無い状態なので、JS/TS 側にも同じ層を作る。

## 現状（実測、2026-08-16）

- **フォーマッタはゼロ。** `.prettierrc*` / `biome.json` / `.editorconfig` のいずれも無い（Prettier はインストールすらされていない）。
- **ESLint は 1 ファイル・実質 3 ルールだけ。** `BefoldApp/eslint.config.mjs` が `viewer-src/**` に対して `no-undef` と `no-unused-vars` を当てるのみ。`eslint:recommended` すら展開していない。
- **未 lint の領域が広い。** `site/**`（8,637 行）、`BefoldApp/BefoldKit/Resources/__tests__/`（4,105 行）、`BefoldApp/scripts/`、`site/public/carousel.js` はどれも検査を受けていない。
- **スタイルが面ごとに割れている。** 行末セミコロンは `site/` が 8,637 行中 15 行なのに対し `BefoldApp/viewer-src` は 1,129 行。import のクォートは site/ 107:0、viewer-src 54:2 でシングルクォート優勢。
- npm プロジェクトは `BefoldApp/` と `site/` の 2 つで、**ルートに package.json は無い**。

## 決めたこと

- **カテゴリは correctness / suspicious / perf / pedantic を error。** style と restriction は入れない。実測で全カテゴリ有効だと site/ だけで 3,965 件出るが、その大半は `no-magic-numbers`(436) / `one-var`(387) / `sort-keys`(332) / `no-async-await`(245) / `no-null`(154) といった「このコードベースが意図して選んでいる書き方」の否定だった。
- **viewer-src とそのテストは TS 移行が終わるまで緩める。** 27 本中 22 本がまだ .js で `checkJs: false` により tsc の検査も受けていない。厳しくすると 555 件出るうえ、多くは TS へ移せば消える。撤去は TASK-499 の Acceptance Criteria に入れた。
- **oxfmt の対象は JS/TS だけに絞る。** 既定のままだと Markdown 812 件（backlog と docs）まで書き換える。Markdown は markdownlint-cli2 が持っている。
- **セミコロンは面ごとの慣習を固定する。** 片方に寄せると寄せられた側は全行が書き換わる。2 つは独立した npm プロジェクトで同時に読む場所でもない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 site/ と BefoldApp の全 JS/TS が Oxlint の対象になっている（ベンダー同梱物・生成物・sample は除外）
- [ ] #2 Oxfmt による整形が全 JS/TS に適用され、以降の差分が整形済み前提になっている
- [ ] #3 既存の ESLint（BefoldApp/eslint.config.mjs）が担保していた検査が Oxlint 側で維持されるか、失われた検査が理由つきで記録されている
- [ ] #4 viewer-src は TS 移行が終わるまで緩めの設定になっており、その理由と厳しくする条件が設定ファイル内に書かれている
- [ ] #5 CI で Oxlint / Oxfmt が実行され、違反でジョブが落ちる
- [ ] #6 pre-commit で Oxlint / Oxfmt が実行され、違反でコミットが止まる
- [ ] #7 既存のテスト・typecheck・ビルドがすべて通る（site の vitest、BefoldApp の jest / typecheck:viewer / check:viewer-bundle）
<!-- AC:END -->
