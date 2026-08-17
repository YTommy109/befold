---
id: TASK-508
title: viewer-src の TS 化で前提が崩れた oxlint 緩和を撤去する
status: Done
assignee: []
created_date: '2026-08-17 02:14'
updated_date: '2026-08-17 14:52'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 738000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-499 で viewer-src が全モジュール .ts になった結果、TASK-498 / TASK-505 で入れた type-aware ルールの緩和のうち、"型情報の無い .js があるから" を理由にしていたものが viewer-src では成立しなくなった。実測（oxlint 1.78.0、`npx oxlint --type-aware -D typescript/<rule> viewer-src`）で viewer-src の件数は次のとおり。

- 0 件: no-unsafe-call / no-unsafe-member-access / no-unsafe-assignment / no-unsafe-argument / no-unsafe-return / no-misused-spread / no-confusing-void-expression / return-await / require-array-sort-compare
- 少数: no-base-to-string 2 / prefer-includes 7 / no-unsafe-type-assertion 20

BefoldApp 全体では no-unsafe-* が 4,474 件出るが、内訳は BefoldKit/Resources/__tests__ の .js 9 本と scripts/*.mjs（実測 94 件）で、viewer-src 由来は 0。現行の設定コメントは "すべて __tests__ の .js 由来" と書いており事実がずれている。

0 件のルールを viewer-src スコープで error に戻して回帰ゲートにし、少数のものは指摘を直したうえで有効化する。件数が多く理由が今も有効な prefer-readonly-parameter-types(102) / strict-boolean-expressions(39) / prefer-nullish-coalescing(30) / no-deprecated(3) / no-unnecessary-type-assertion(5) は据え置く（DOM 型定義の揺れで鳴ったり止んだりする、という理由は TS 化と独立）。

あわせて "off の一覧は site/ と BefoldApp/ で揃える" という現行規約は成立しなくなる（site/ は外部 JSON の絞り込みで no-unsafe-* が 100 件超残る）。"プロジェクトレベルの off は揃え、ディレクトリ単位の再有効化は理由つきで書く" へ言い換える。

oxfmt は変更しない。面ごとのセミコロン差・sortImports・対象拡張子の絞り込みはいずれも TS 化と独立した選択で、崩れた前提が無い。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 BefoldApp/.oxlintrc.json に viewer-src/** スコープの override が入り、viewer-src で 0 件だった 9 ルールが error になっている
- [x] #2 prefer-includes / no-base-to-string / no-unsafe-type-assertion の viewer-src の指摘（実測 29 件）が解消され、3 ルールも viewer-src スコープで error になっている
- [x] #3 no-unsafe-* を全体で off にしている理由のコメントが実態（__tests__ の .js に加えて scripts/*.mjs）に合っている
- [x] #4 BefoldApp/ と site/ の両方で npm run lint / format:check / typecheck / test が通る
- [x] #5 .claude/CLAUDE.md の JS/TS コーディング規約が、面ごとの off 一覧の揃え方とディレクトリ単位の再有効化の扱いを反映している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `BefoldApp/.oxlintrc.json` に `viewer-src/**` スコープの override を追加し、12 ルールを error に戻した。うち 9 つ（no-unsafe-call / no-unsafe-member-access / no-unsafe-assignment / no-unsafe-argument / no-unsafe-return / no-misused-spread / no-confusing-void-expression / return-await / require-array-sort-compare）は viewer-src で実測 0 件だったので、いま守れている状態の回帰ゲートとして固定しただけ。残る 3 つ（prefer-includes 7 / no-base-to-string 2 / no-unsafe-type-assertion 20）は指摘を解消したうえで有効化した。
- プロジェクトレベルの off はそのまま。BefoldKit/Resources/__tests__ の .js 9 本と scripts/*.mjs（実測 94 件）が型情報を持たないため、全体では外せない。

## コード修正（29 件）

- `prefer-includes`: `indexOf(x) !== -1` を `includes(x)` へ（csv-html / find / path-refs / renderers）。
- `no-base-to-string`: diff-html.ts の text と mermaid.ts の err。err は `instanceof Error` で分岐する形にした。
- `no-unsafe-type-assertion`（本体）: `nodeType === 1 / 3` を見てから `as Element` / `as Text` していた箇所を **すべて `instanceof Element` / `instanceof Text` の型ガードへ置き換えた**（find.ts / path-refs.ts / reference-clicks.ts / keyboard.ts / render.ts / fonts.ts / zoom.ts）。判定内容は等価で、表明が消えた分だけ実行時の裏付けが増えている。
- `find.ts:findInputElement` は `getElementById(...) as HTMLInputElement` をやめ、`instanceof HTMLInputElement` で確かめて違えば TypeError を投げる形にした。呼び出し 4 箇所（find.ts:323 / 358 / 429 / 492）はいずれも直後に value / placeholder / classList を触るため、要素が無い場合の結果は従来どおり TypeError で変わらない（投げる行が 1 行早くなるだけ）。
- `path-refs.ts` の `Object.create(null) as Record<string, true>` は `Map<string, true>` へ。`__proto__` を素の `{}` に吸われないという当初の意図は Map でも保たれる。
- `path-refs.ts` の `Array.prototype.slice.call(node.childNodes) as Node[]` は `Array.from(node.childNodes)` へ（2 箇所）。
- `encoding.ts`: `base64ToBytes` の戻り値型を `Uint8Array<ArrayBuffer>` に明示した。指摘一覧には無かったが、renderers.ts:69 の `as BlobPart` を外すために必要。既定の `Uint8Array` は SharedArrayBuffer 上のものを含み Blob へ直接渡せない一方、ここで確保するのは常に自前の ArrayBuffer なので実行時の値は変わらない。
- `abbr`/`disable` コメントによる抑止と `as unknown as` は 1 件も使っていない。

## 検証（すべて BefoldApp/ で実行）

- `npx oxlint --type-aware --report-unused-disable-directives`: 0 件
- `npm run typecheck:viewer`（tsc --noEmit）: 通過
- `npm test`: 8 suites / 445 tests すべて通過
- `npm run format:check`: 40 ファイルすべて整形済み
- `npm run check:viewer-cycles`: 循環 import なし（26 モジュール）
- `npm run build:viewer` でバンドルを再生成済み

## 見送り

件数が多く、理由が TS 化と独立に成立しているものは据え置いた: prefer-readonly-parameter-types(102) / strict-boolean-expressions(39) / prefer-nullish-coalescing(30) / no-unnecessary-type-assertion(5) / no-deprecated(3)。oxfmt は変更なし（面ごとのセミコロン差・sortImports・対象拡張子の絞り込みはいずれも TS 化と独立した選択で、崩れた前提が無い）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-src の TS 化（TASK-499）で前提が崩れた oxlint の type-aware 緩和を撤去した。BefoldApp/.oxlintrc.json に viewer-src/** スコープの override を置き、12 ルールを error に戻している。うち 9 つは viewer-src で実測 0 件のため回帰ゲートとして固定しただけで、残り 3 つ（prefer-includes / no-base-to-string / no-unsafe-type-assertion）は 29 件の指摘を解消して有効化した。中心は nodeType 比較 + as Element/Text という書き方を instanceof の型ガードへ置き換える変更で、要素が想定と違ったときに実行時まで気づけない箇所が消えた。抑止コメントと as unknown as は使っていない。プロジェクトレベルの off は __tests__ の .js 9 本と scripts/*.mjs（実測 94 件）が型情報を持たないため据え置き。検証は BefoldApp/ で oxlint 0 件・tsc 通過・jest 8 suites 445 tests 通過・format:check 40 ファイル整形済み・循環 import なしを実測。oxfmt は前提が崩れていないため変更なし。
<!-- SECTION:FINAL_SUMMARY:END -->
