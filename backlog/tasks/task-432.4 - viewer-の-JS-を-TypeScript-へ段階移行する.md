---
id: TASK-432.4
title: viewer の JS を TypeScript へ段階移行する
status: In Progress
assignee:
  - '@Tommy109'
created_date: '2026-08-10 12:57'
updated_date: '2026-08-11 14:30'
labels: []
dependencies:
  - TASK-432.3
parent_task_id: TASK-432
priority: low
type: chore
ordinal: 112400
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
バンドル基盤とモジュール分割が済んだ後、`allowJs` を使ってファイル単位で TypeScript へ移行する。

## 型付けの価値が高い箇所

- Swift ↔ JS のブリッジ契約。`BefoldKit/ViewerBridge.swift`（374 行 + `+Diff.swift` / `+PayloadKeys.swift`）が単一情報源で、JS→Swift の 7 メッセージ、Swift→JS の引数なし関数 9 個、注入グローバル 8 個（`_mmdInitialZoom` / `_mmdHostFeatures` / `_mmdBannerStrings` / `_mmdInitialFindOptions` ほか）を定義している。JS 側は `viewer-main.js:2-8` の `_MSG_*` 定数と `:75, 84, 93, 102, 185, 889, 977, 985, 1360` の読み取りで対応しており、現状は文字列の一致を `ViewerBridgeContractTests` がソーステキストの照合で担保している。
- 表示モード・レンダラの分岐（TASK-414 の乖離が起きた箇所）。

## 決めること

- ブリッジ契約の型を手書きするか、`ViewerBridge.swift` から生成するか。生成なら生成物のズレ検証が要る（TASK-432.1 で入れる一致検証と同じ仕組みに乗せられる）。
- strict の度合いと、移行途中の混在をどう扱うか。
- `site/` は TypeScript 5.7 + vitest を使っている。バージョンや設定を揃えるか、独立させるか。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 TypeScript のビルドと型検査が npm スクリプトから実行できる
- [ ] #2 型検査が CI で実行され、エラーで落ちる
- [ ] #3 少なくともブリッジ契約に関わるモジュールが TypeScript へ移行されている
- [ ] #4 ブリッジ契約の型を手書きするか生成するかの判断が理由つきで記録されている
- [ ] #5 既存テストが通り、ケース数が減っていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結論を反映した計画（実装着手前に 1 回実施済み）

### 決めたこと 1: ブリッジ契約の型は手書き。生成しない。ただし手書きするのは「値」であって「型」ではない。
既存の ViewerBridgeContractTests が viewer-bundle.js の`値`を読んで Swift と双方向に照合しており（befoldTests/ViewerBridgeContractTests.swift:82-109 でペイロードキーの双方向一致、:247-252 で _MSG_* 定数の抽出）、破れたら落ちる担保が既にある。生成方式にすると「生成物のズレ検証」という三本目の担保が要る。TS 側は `export const _MSG_X = "literal"` を保ち、型は `typeof` で導出する。型を別途宣言しない（二重管理を作らない）。

**この方式が成立する条件（守らないと測定が空振りする）**: 契約テストは成果物の`文字列の形`を測っている。次の 2 つを保つこと。
- `_MSG_*` はフラットな const 宣言のまま（オブジェクト名前空間へ畳まない）。正規表現 `(?:var|let|const)\s+(_MSG_[A-Z_]+)\s*=\s*"([A-Za-z]+)"` が拾う形。
- `_mmdPostMessage(_MSG_X, { ... })` の第 2 引数は直書きのオブジェクトリテラルのまま（型別名の変数へ逃がさない）。正規表現がネスト無しのリテラルしか拾えない。

**空振りが黙って通る抜け道は無い**ことを確認済み: 抽出が 0 件になれば :250 の `#expect(!pairs.isEmpty)` が落ち、一部だけ拾えなくなれば declaredMessagesHavePostSites（:99-109）が「送信サイトが無い」で落ちる。

### 決めたこと 2: full strict + allowJs / checkJs:false。
tsconfig: strict, noUncheckedIndexedAccess, allowJs:true, checkJs:false, noEmit:true, moduleResolution Bundler, target ES2022, lib [ES2022, DOM], isolatedModules, verbatimModuleSyntax。出力は従来どおり esbuild。checkJs を false にするのは、未移行の .js を型エラー源にせず各ステップで CI を緑に保つため。移行済みモジュールだけが strict の対象になるので full strict と段階移行は両立する。

### 決めたこと 3: site とはバージョンだけ揃え、設定は独立。
別 package.json・別ランタイム（safari17 のブラウザ / Cloudflare Workers）で lib と types が噛み合わないため tsconfig は共有しない。typescript は site と同系（^5.7）。

### 今回の移行範囲
bridge.js -> bridge.ts、expose.js -> expose.ts、window._mmd* 注入グローバルを宣言する viewer-globals.d.ts、および globals を読む小物 2 つ（fonts.js / truncation.js）。混在が双方向（.ts が .js を import / .js が .ts を import）で成立することを実証する。index.js / main.js / find.js 等は次タスクへ。

## /review-design で出た指摘と対処

1. **判定の真実の源（項目1）**: 「型検査・lint が効いているか」をファイル拡張子で決めているため、eslint.config.mjs:64 の `files: ["viewer-src/**/*.js"]` を放置すると .ts が`黙って無検査`になる（対象 0 件でも lint は成功する = 「空だから安全」型の穴）。-> 対処: eslint の files を `viewer-src/**/*.{js,ts}` へ広げ、npm script も明示 glob にする。tsconfig の include は列挙ではなくディレクトリ全体（`viewer-src/**/*`）にして、`追記漏れする列挙`をそもそも作らない。

2. **測るものと守るものの一致（項目7）**: 上記「決めたこと 1」の条件として記録。抜け道が無いことは確認済み。

3. **消費経路と兄弟判断の全列挙（項目3）**: `.js` 決め打ちの兄弟箇所は 4 つ。README への記録だけで済ませない。
   - eslint.config.mjs:64 の files -> 今回直す（黙って無検査になる唯一の箇所）
   - scripts/check-viewer-cycles.mjs:17 のエントリ -> 今回 index.js を移さないので変更不要。移した場合は esbuild がエントリを見つけられず`落ちる`ので黙って壊れない
   - viewerMainHarness.js の TEST_ENTRY の `./main.js` -> 同上（esbuild は .js 指定を .ts へ解決するため、移しても黙って動く。実測スパイクで確認済み）
   - jest の設定不在 -> 今回追加する

4. **決めた粒度を守らせるもの（項目9）**: 同名 basename の .js と .ts が同居すると、esbuild（resolveExtensions が .ts 優先）と jest（moduleFileExtensions 順）で解決先が食い違い、`テストと本番で別のファイルを見る`状態が黙って成立する。-> 対処: jest の moduleFileExtensions を esbuild と同じ優先順（ts を js より先）にして、同居しても解決が一致する形にする。新しい検査スクリプトは足さない。

5. **既存の不変条件との衝突（項目2）**: 不変条件（viewer-src とバンドルの同期 / 本番とテストでグローバル集合が一致 / 循環禁止）はいずれも迂回しない。加えて今回に限り強い検証が使える -> **型注釈は消えるだけなので、コードの意味を変えなければ viewer-bundle.js は差分ゼロのはず**。差分が出たら意図しない意味変化なので、AC#5 の補強として`バンドル差分ゼロ`を確認する。

6. 項目4（新しい状態の表示）/ 項目5（ライフサイクル・順序）/ 項目6（高頻度経路）/ 項目8（非同期の世代管理）/ 項目10（型グループ行数）: 非該当。ユーザー向け表示は変わらず、実行時の初期化順も実行時コストも不変（型は消える）。非同期処理を含まず、Swift 側の型は 1 行も触らない。

## 手順

1. devDependencies に typescript(^5.7) / @babel/preset-typescript / typescript-eslint を追加
2. BefoldApp/tsconfig.json を追加（include は viewer-src ディレクトリ全体 + 型宣言）
3. babel.config.cjs に preset-typescript を追加、package.json の jest 設定に moduleFileExtensions（ts 優先）と moduleNameMapper（相対 .js を剥がす）を追加
4. eslint.config.mjs を {js,ts} へ広げ、.ts に typescript-eslint parser を割り当て
5. npm script `typecheck:viewer` を追加し、ci.yml の js-test ジョブへ 1 ステップ追加（AC#2）
6. viewer-globals.d.ts を追加（window._mmd* の 8 グローバル）
7. bridge.js / expose.js / fonts.js / truncation.js を .ts へ移行（git mv + 型付け）
8. 検証: npx jest（417 件から減っていないこと）/ typecheck:viewer / lint:viewer / check:viewer-cycles / check:viewer-bundle（差分ゼロ）/ swift test --filter ViewerBridgeContract / swift build
9. viewer-src/README.md と docs/dev/rules 配下を追随

## 次タスクへの申し送り（受け取り側の AC にする）
残りモジュールの移行タスクでは、index.js / main.js を .ts にする際に check-viewer-cycles.mjs:17 のエントリパスを併せて変える（エントリだけは esbuild の拡張子解決が効かず落ちる）。
<!-- SECTION:PLAN:END -->
