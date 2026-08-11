---
id: TASK-432.4
title: viewer の JS を TypeScript へ段階移行する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-10 12:57'
updated_date: '2026-08-11 21:29'
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
- [x] #1 TypeScript のビルドと型検査が npm スクリプトから実行できる
- [x] #2 型検査が CI で実行され、エラーで落ちる
- [x] #3 少なくともブリッジ契約に関わるモジュールが TypeScript へ移行されている
- [x] #4 ブリッジ契約の型を手書きするか生成するかの判断が理由つきで記録されている
- [x] #5 既存テストが通り、ケース数が減っていない
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

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決めたこととその理由

- **ブリッジ契約の型は手書きせず、値から導出した（AC#4）。** bridge.ts のメッセージ名は `var _MSG_* = '...' as const` のフラットな宣言のまま残し、型 `ViewerMessageName` は `typeof` で導く。理由は、値の一致を ViewerBridgeContractTests が既に成果物 viewer-bundle.js の文字列として Swift と双方向に照合しているため（ViewerBridgeContractTests.swift:82-109 / :247-252）。型を別に宣言すると「Swift の値・JS の値・JS の型」の 3 つを揃える形になり、生成方式にすると「生成物のズレ検証」という三本目の担保が要る。**手書きするのは値だけ**にして、既存テストが見ている場所を単一情報源にした。
  - この方式が成立する条件（`_MSG_*` をフラットな const のまま保つ / postMessage の第 2 引数を直書きリテラルのまま保つ）は product-code.md の JS 規約と bridge.ts のコメントに明記した。条件を破って抽出が空振りしても、declaredMessagesHavePostSites（:99-109）と `#expect(!pairs.isEmpty)`（:250）が落ちるため黙って通る抜け道は無い。

- **hostFeatures のキー名に契約テストを 1 本足した。** viewer-globals.d.ts の `ViewerHostFeatures` は Swift のキー名を JS 側へ手書きするため、放置すると手書き分が担保なしになる。実際、bannerStrings / findStrings には照合があるのに hostFeatures には無く、キー名が片側だけ変わると isHostFeatureEnabled が「未指定 = 有効」へ静かに縮退して抑止が効かなくなる経路だった（QuickLook の Space 抑止と同じ型の事故が過去に起きている）。照合語に `_mmdHostFeatures, "<key>"` と global 名を含めたのは、キー名だけで探すと bannerStrings の "loadMore" に一致して誤って通るため。**自己検証済み**: Swift 側のキーを spaceScroll -> spaceScrollX に一時変更して失敗を確認し、復元した。

- **checkJs は false（strict は full strict）。** 未移行の .js を型エラー源にしないことで、移行の各ステップで CI が緑のまま進む。移行済みの .ts だけが strict の対象になるので full strict と段階移行は両立する。「型検査されるのは .ts だけ」という誤解を生まないよう、viewer-src/README.md・product-code.md・testing.md の 3 箇所に明記した。
  - tsconfig の `include` はファイル列挙ではなくディレクトリ全体にした。移行のたびに追記する列挙を作ると、追記漏れたモジュールが「型が付いた見た目のまま一度も検査されない」形で静かに残る。

- **site とはバージョンだけ揃え、設定は独立。** 別 package.json・別ランタイム（safari17 のブラウザ / Cloudflare Workers）で lib と types が噛み合わないため tsconfig は共有しない。typescript は 5.9.3 を exact 指定（site は ^5.7.2 で同じ 5.9 系に解決される）。exact にしたのは既存の esbuild / eslint / @babel/core と同じ方針で、CI の型検査が無関係な PR で突然落ちるのを避けるため。

- **同名 basename の .js/.ts が並んだときの解決先の食い違いを構造で塞いだ。** esbuild は resolveExtensions の既定で .ts を優先するが、jest は moduleFileExtensions 順で決める。既定のままだと両方存在したときテストと本番が別ファイルを見る。新しい検査スクリプトを足すのではなく、jest 側を ts -> js の順にして**同居しても解決が一致する**形にした。

## バンドルが strict mode になった件（設計判断）

tsconfig.json を置いた時点で、esbuild が成果物の先頭に `"use strict";` を出すようになった。**実測でトリガーを特定した**: 原因は移行済み .ts の有無ではなく、esbuild が tsconfig.json を自動検出して `strict: true` が含む `alwaysStrict` を尊重すること。スクラッチパッドの最小再現で、(a) .ts を含むグラフでも tsconfig が無ければ付かない、(b) .js だけのグラフでも tsconfig があれば付く、(c) `alwaysStrict: false` で抑止できる、の 3 点を確認した。

**抑止せずそのまま採用した。** ソースは ESM（常に strict）として書かれ、Jest 側は babel が CommonJS へ落とす際に `"use strict"` を付けるため、**テストは以前から strict で走っていた**。付けないと出荷される成果物だけが sloppy mode という、テストと本番のずれが残る。抑止はそのずれを復活させる方向に働く。

安全性の裏付け:
- viewer-src 全体に `this` / `with` / 8 進リテラル / `arguments.callee` の出現が 0 件（rg で実測）
- 暗黙のグローバル代入は eslint の no-undef（error）が全 .js を対象に押さえている
- ベンダー（mermaid / markdown-it / highlight.js / DOMPurify）は viewer.html が別の classic script として読むため、この prologue の影響を受けない
- 実 WKWebView での webview-smoke が PASS

理由と「抑止しないこと」は viewer-src/README.md に節を立てて記録した。

## バンドル差分の内訳（意図しない意味変化が無いことの確認）

型注釈は消えるだけなので、コードの意味を変えなければバンドルは差分ゼロになるはず、という前提で差分を全数確認した。実際の差分は 6 行のみで、すべて説明がつく。

- `"use strict";` の追加 1 行（上記のとおり意図した採用）
- `// viewer-src/bridge.js` -> `.ts` などのパスコメント 3 行
- `.replace("{count}", lineCount)` -> `String(lineCount)` 1 行。replace の第 2 引数は string 型なので number を渡すと型エラーになる。実行時は ToString で同じ結果になるため、キャストで型だけ通すより明示した

DOM 要素の取得（getElementById）は非 null 表明（!）で通し、実行時の形を変えていない。id が viewer.html 側から消えた場合は表明の有無にかかわらず同じ行で TypeError になるため、検知を緩めていない。

## 検証（すべて実測）

- npx jest: 417 passed / 6 suites（移行前と同数。ベースラインも 417）
- npm run typecheck:viewer: エラー 0。**AC#2 の自己検証**として fonts.ts へ意図的な型エラーを 1 行足すと exit code 2 で落ち、戻すと 0 に戻ることを確認した（CI は同じコマンドを叩く）
- npm run lint:viewer: 0 件（対象を viewer-src/**/*.{js,ts} へ広げた後）
- npm run check:viewer-cycles: 循環なし（25 モジュール）
- npm run check:viewer-bundle: exit 0（コミット後）
- swift build: Build complete / swift test: **1416 tests / 208 suites すべて pass**（移行前 1415 + 今回追加した契約テスト 1 本）
- swift test --filter ViewerBridgeContract: 11 件 pass（移行前 10 件）
- xcodebuild build -scheme befold: BUILD SUCCEEDED
- swift scripts/webview-smoke.swift: PASS（strict mode バンドルが実 WKWebView で稼働することの確認を含む）
- markdownlint-cli2: 70 files / 0 issues
- scripts/check-doc-symbols.sh: exit 0
- 型検査が実際に効いていることの実測: 移行直後の truncation.ts で TS7006（暗黙の any）3 件と TS18047（getElementById の null）9 件を検出した

## 移行前に潰した未知数（実測スパイク）

esbuild 0.28.2 で、`.js` の importer が書いた `import "./a.js"` は `a.ts` へ解決される（`.ts` のみ存在する状態でバンドル成功）。したがって混在移行で import 指定子の書き換えは不要。**ただしエントリだけは拡張子解決が効かない**。

## 追随させたドキュメント

BefoldApp/viewer-src/README.md（「TypeScript への段階移行」節を新設。モジュール表の .ts 化、コマンド一覧に typecheck:viewer）/ docs/dev/rules/product-code.md（JS 規約に混在の扱いとブリッジ契約の型方針）/ docs/dev/rules/testing.md（Jest が .ts をどう解決するか、Jest では型が検査されないこと）/ docs/dev/rules/workflow.md / .claude/commands/check.md / .github/workflows/ci.yml

## 次タスクへの申し送り（受け取り側の AC にすること）

残りモジュールを移行するタスクでは、`index.js` / `main.js` を .ts にする際に **`package.json` の build:viewer と `scripts/check-viewer-cycles.mjs`（現在 viewer-src/index.js を決め打ち）のエントリパスを併せて変える**。エントリだけは esbuild の拡張子解決が効かない。なお両者ともエントリを見つけられなければ落ちるため、黙って壊れることはない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-src/ を TypeScript へ段階移行する基盤（allowJs による .js/.ts 混在、tsc --noEmit の型検査、CI ステップ）を通し、ブリッジ契約に関わる bridge / expose と、注入グローバルを読む fonts / truncation を .ts へ移した。window 注入値の型は viewer-globals.d.ts に集約した。

ブリッジ契約の型は手書きせず、bridge.ts のリテラル値から as const で導出する形にした。値の一致は ViewerBridgeContractTests が成果物 viewer-bundle.js を読んで Swift と双方向に照合しており、型を別に宣言すると Swift の値・JS の値・JS の型の 3 重管理になるため。成立条件（_MSG_* をフラットな const のまま保つ / postMessage の第 2 引数を直書きリテラルのまま保つ）は規約とコメントに明記し、条件が破れて抽出が空振りしても declaredMessagesHavePostSites と !pairs.isEmpty が落ちることを確認した。あわせて、これまで照合が無く手書き分が担保なしだった hostFeatures のキー名に契約テストを 1 本足し、Swift 側のキーを一時的にずらして実際に落ちることを自己検証した。

tsconfig.json を置くと esbuild が成果物へ "use strict" を出す。トリガーが .ts の有無ではなく tsconfig の存在であることを最小再現で特定したうえで、抑止せず採用した（ソースは ESM で Jest も babel の CommonJS 変換で strict のため、抑止するとテストと本番のずれが残る）。安全性は this/with/8 進リテラルの不在、no-undef による暗黙グローバルの排除、ベンダーが別 script であること、実 WKWebView の webview-smoke PASS で裏付けた。

検証: npx jest 417 passed / 6 suites（移行前と同数）、typecheck:viewer エラー 0（意図的な型エラーで exit 2 になることを自己検証）、lint:viewer 0 件、check:viewer-cycles 循環なし、check:viewer-bundle exit 0、swift build / swift test 1416 tests 208 suites すべて pass（移行前 1415 + 追加した契約テスト 1 本）、xcodebuild BUILD SUCCEEDED、webview-smoke PASS、markdownlint 0 issues、check-doc-symbols exit 0。バンドル差分は 6 行のみで全数の内訳を確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
