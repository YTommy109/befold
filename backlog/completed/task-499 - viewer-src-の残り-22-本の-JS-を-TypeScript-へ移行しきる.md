---
id: TASK-499
title: viewer-src の残り 22 本の JS を TypeScript へ移行しきる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-16 07:20'
updated_date: '2026-08-16 15:56'
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
- [x] #1 viewer-src から .js が無くなり、全モジュールが .ts になっている
- [x] #2 BefoldApp/tsconfig.json の allowJs / checkJs 設定が移行完了に合わせて見直されている
- [x] #3 Oxlint の viewer-src 向け緩和（TASK-498 で入れた override）が撤去され、site/ と同じ厳しさの設定が適用されている
- [x] #4 既存の jest テストが通り、ケース数が減っていない
- [x] #5 check:viewer-bundle が通る（バンドル成果物とソースがずれていない）
- [x] #6 移行完了後に BefoldApp へ oxlint の type-aware linting（TASK-505 で site/ に導入したもの）を入れるかを判断し、入れるなら site/ と同じ 3 ルール以上を有効化している。判断結果は Implementation Notes に残す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ベースライン計測（jest 445 件 / typecheck clean / esbuild 動作）
2. 依存の浅い順に波（wave）で .js → .ts へ移行し、各波で typecheck + jest を通す
   - wave 1: encoding / vendor / color-scheme / doc-path / document-state / view-options
   - wave 2: code-html / scroll / find / path-refs / zoom
   - wave 3: csv-html / diff-html / markdown / mermaid / keyboard / reference-clicks / renderers
   - wave 4: render / init / main / index
3. .js が無くなった時点で package.json のエントリ（build:viewer / check-viewer-cycles.mjs）を .ts へ更新
4. tsconfig.json の allowJs / checkJs を見直す（allowJs 不要になる）
5. .oxlintrc.json の viewer-src 向け override を撤去し、残る指摘を実測して個別対処
6. oxlint --type-aware を BefoldApp へ導入するか判断し、Notes に残す
7. viewer-bundle.js を再生成し check:viewer-bundle を通す
8. viewer-src/README.md と docs/dev/native-app-design.md の記述を実態へ追随させる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
2026-08-16: TASK-505 で site/ に `oxlint --type-aware` を導入した際、BefoldApp/ でも実測した。結果は 5,263 件（`no-unsafe-call` 2,667 / `no-unsafe-member-access` 1,836 / `no-unsafe-assignment` 416 ほか）で、原因は BefoldApp/tsconfig.json の `checkJs: false` により viewer-src の大半が型無しの .js のまま扱われること。本タスクの完了が前提条件になるため、BefoldApp への導入判断は本タスクへ申し送った（AC を 1 件追加）。site/ 側で有効化したのは `typescript/no-floating-promises` / `no-misused-promises` / `await-thenable` の 3 つで、それ以外は site/.oxlintrc.json に理由つきで off にしてある。

2026-08-17 完了。

## 移行

viewer-src の .js 22 本を依存の浅い順に 4 波で .ts へ移した（葉 6 / 中核 5 / 描画・入力 7 / エントリと render 4）。各波で typecheck + jest + 循環 import 検査を通している。既存 .ts（bridge / truncation / fonts / expose）の書き方に揃え、var・関数式・日本語コメントはそのまま残して型注釈だけを足した。

型の逃げ道は 1 箇所だけ残した: zoom.ts の setZoomStyle（CSS zoom は非標準で型定義が文字列しか受け取らないが、実装は数値を倍率として解釈する）。dataset への数値代入は暗黙の文字列化に頼らず String() で明示した。

副次的に直したもの:
- @types/markdown-it を devDependency へ追加（markdown-it 14 は型を同梱しない）
- document-state の lang を string | null → string | undefined。ViewerBridge.contentCallScript は lang を文字列で渡すか引数ごと省略するかのどちらかで、null は来ない（BefoldKit/ViewerBridge.swift:117-126 で確認）
- mermaid は npm の型を import せず、mermaid.ts 内に使う範囲だけの interface をローカル宣言した。型 import で esbuild が 3.2MB の実体を引き込むのを避けるため

## tsconfig

allowJs: true / checkJs: false → allowJs: false（checkJs は不要になったので削除）。allowJs を単に外すのではなく false を明示してあるのは、.js を足すと import が解決できずその場で落ちる形にして「解決対象には入るが型検査は受けない」穴が復活しないようにするため。

## oxlint

override 撤去で 482 件。うち no-underscore-dangle(218) と prefer-query-selector(115) は移行と無関係な恒久的選択（_mmd 接頭辞は Swift との契約、getElementById は意図した選択）なので、理由つきの別 override へ分離した。残る 149 件は 46 件を --fix、残りを手当てした。

**--fix は機械任せにできない（実測）。** prefer-at が codeTable.rows[len-1] を rows.at(-1) に書き換え、HTMLCollection に .at が無いため「改行で終わらなかったチャンクの続きは前の行に結合される」が落ちた。以降は 1 件ずつ実行時の等価性を確認してから適用している。等価でないものは理由つきで無効化した（charCodeAt→codePointAt はサロゲートペアを畳んでバイト列が壊れる / parseFloat→Number は単位付き CSS 計算値 '22.4px' が NaN になり縮退の分岐が変わる、など）。

## AC #6 の判断: BefoldApp へ type-aware linting を入れる

TASK-505 の時点で 5,263 件だったのは checkJs: false で viewer-src の大半が .js だったため。TS 化後に測り直すと 4,749 件で、**うち 4,423 件（no-unsafe-*）はすべて BefoldKit/Resources/__tests__ の .js 由来。viewer-src は 0 件**（viewer-src の内訳は prefer-readonly-parameter-types 102 / strict-boolean-expressions 39 / prefer-nullish-coalescing 30 ほか、いずれも site/ で off 済みのもの）。

したがって site/ と同じ off 一覧を当てれば残り 8 件で、導入コストは無い。site/ と同じ 3 ルール（no-floating-promises / no-misused-promises / await-thenable）を error にした。

有効化の効果は導入時点で出た: no-floating-promises が viewer-src の 2 箇所を検出した（_mmdRerenderCurrent の render()、appendChunk の _mmdRunMermaid）。どちらもコメントで意図は書かれていたが式としては区別が付かない fire-and-forget だったので、void を置いて明示した。off の一覧は site/.oxlintrc.json と揃えてあり、片方だけ緩めないことを両ファイルのコメントに書いた。

## 検証（すべて実測）

- npx jest: 445 件パス（移行前と同数。ケース数は減っていない）
- npm run typecheck:viewer: エラー 0
- npm run lint（--type-aware 付き）: 指摘 0
- npm run format:check: 整形ずれ 0
- npm run check:viewer-cycles: 循環なし（26 モジュール）
- npm run check:viewer-bundle: exit 0（バンドルとソースが一致）
- swift test --filter ViewerBridgeContract: 11 件パス（再生成したバンドルに対して Swift 側の契約が保たれている）
- swift scripts/webview-smoke.swift: PASS（CSP 下でバンドル稼働・mmd/md 描画・ハイライト・外部画像と data: iframe のブロック・PDF blob 表示）
- markdownlint-cli2: 0 issues

## 追随させた文書

- BefoldApp/viewer-src/README.md: モジュール表の拡張子、「TypeScript への段階移行」節を「TypeScript」（完了状態）へ書き換え
- docs/dev/native-app-design.md: ディレクトリ図の記述を TypeScript / index.ts へ
- .claude/CLAUDE.md: viewer-src の緩和と type-aware の記述を実態へ
- .github/workflows/ci.yml: typecheck ステップのコメント（checkJs: false → allowJs: false）
- .oxlintrc.json（ルート）: コメント内の render.js → render.ts
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-src の .js 22 本（約 3,000 行）を TypeScript へ移しきり、viewer-src から .js が無くなった。依存の浅い順に 4 波で進め、各波で typecheck・jest・循環 import 検査を通している。tsconfig は allowJs: false にして「解決対象だが型検査は受けない」穴が復活しない形にした。

TASK-498 の暫定緩和（oxlint override）を撤去し、出た 482 件のうち恒久的選択の 2 ルール（_mmd 接頭辞・getElementById）を理由つきの別 override に分離、残る 149 件を 1 件ずつ処理した。oxlint --fix は prefer-at が HTMLCollection に .at(-1) を生成してテストを 1 件落としたため機械任せにせず、等価でない書き換えは理由つきで無効化している。

AC #6 は「入れる」と判断した。TASK-505 で 5,263 件だった type-aware の指摘は TS 化後 4,749 件で、うち 4,423 件が __tests__ の .js 由来（viewer-src は 0 件）。site/ と同じ off 一覧で残り 8 件になるため導入コストが無く、有効化した no-floating-promises が viewer-src の意図的な fire-and-forget 2 箇所を検出したので void で明示した。

検証: jest 445 件パス（移行前と同数）、tsc --noEmit エラー 0、oxlint --type-aware 指摘 0、format:check ずれ 0、check:viewer-cycles 循環なし、check:viewer-bundle exit 0、swift test --filter ViewerBridgeContract 11 件パス、swift scripts/webview-smoke.swift PASS。
<!-- SECTION:FINAL_SUMMARY:END -->
