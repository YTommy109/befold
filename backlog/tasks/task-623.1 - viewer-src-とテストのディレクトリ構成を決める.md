---
id: TASK-623.1
title: viewer-src とテストのディレクトリ構成を決める
status: Done
assignee:
  - '@claude'
created_date: '2026-09-14 11:57'
updated_date: '2026-09-15 01:53'
labels: []
dependencies: []
parent_task_id: TASK-623
priority: medium
type: chore
ordinal: 818000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`BefoldApp/viewer-src/` は 37 ファイルがフラット、テストは `BefoldApp/BefoldKit/Resources/__tests__/` に 16 本フラットに置かれている（2026-09-14 時点）。テストを TypeScript へ移す前に置き場所と階層を決めないと、移設とリネームを二度やることになる。背景と実測は親 TASK-623 の Description を参照。

決める際に効く制約（2026-09-14 時点、着手時にコードで裏を取ること）:

- `tsconfig.json` の `include` はディレクトリ全体で `types: []`。テストを `viewer-src/` 配下に置くと本体の型設定がかかる。
- `.oxlintrc.json` の `viewer-src/**` override が `no-unsafe-*` を error にしている。
- `npm run check:viewer-cycles`（`scripts/check-viewer-cycles.mjs`）、esbuild のエントリ（`viewer-src/index.ts`）、barrel の `main.ts`、`viewer-src/README.md` のファイル表が階層変更に追随する必要がある。
- `scripts/check-doc-citations.sh` が `docs/dev/**` と ADR 内のパス引用の実在を pre-commit で検査する。
- site/ はソース（`src/`）とテスト（`test/`）を分けている前例がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 `viewer-src` の階層（フラットのまま / 関心ごとのサブディレクトリ）と、テストの置き場所（ソースと同居 / 隣接ディレクトリ）が、採らなかった案とその理由つきで記録されている
- [x] #2 決めた構成で `tsconfig`・oxlint の override・循環検査・esbuild のエントリ・doc 引用検査がどう変わるかが列挙されている
- [x] #3 不可逆な判断を含む場合は ADR（`backlog/decisions/`）として記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. テストの import 実態と tsconfig / oxlint / Package.swift / project.yml / 文書のパス引用を実測する
2. viewer-src の階層とテストの置き場所を、採らなかった案と理由つきで決める
3. 決めた構成で各設定・検査がどう変わるかを列挙し、ADR の要否を判断する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 決定（2026-09-15）

### 1. viewer-src はフラットのまま（サブディレクトリに分けない）

根拠（実測）:
- 36 モジュール・計 6,071 行（`wc -l BefoldApp/viewer-src/*.ts`）。関心の束は既にファイル名の接頭辞で表れている（`bar-*` 3 本、`csv-*` 3 本、`jump*` 2 本、`render*` 2 本）。束になるのは 2〜3 本で、残り約 20 本は単独の関心（bridge / encoding / fonts / ime / scroll / zoom / keyboard ...）。サブディレクトリにしても 1 ファイルだけのディレクトリが大半になる。
- 各ファイルの責務は `viewer-src/README.md` の表が 1 行ずつ持っている。階層を作っても情報は増えない。
- サブディレクトリ化は全モジュールの import 指定子（`./bridge.js` → `../bridge.js`）を書き換える内容変更になり、623.2 の「移動だけ」と両立しない。

採らなかった案: 関心ごとのサブディレクトリ（find/ jump/ bar/ csv/ diff/ render/）。上記のとおり束が小さく、import の書き換えコストに見合う整理効果が無い。後から分けるのも git mv と import の書き換えで戻せるため、今決め切る必要が無い。

### 2. テストは viewer-src の隣の `BefoldApp/viewer-test/` に置く（ソースと同居させない）

根拠（実測）:
- テストはモジュール単位ではなく公開面の barrel を相手にしている。16 本のうち 7 本は `viewer-src/main.js` を require、8 本は `support/viewerMainHarness.js`（esbuild で main を IIFE 化して jsdom で評価）経由、個別モジュールを直接読むのは `viewer-path-refs.test.js`（path-refs.js）1 本だけ（`rg -n "require\(" __tests__/*.test.js`）。`foo.ts` の隣に `foo.test.ts` を置く対応関係がそもそも無い。
- viewer-src 配下に置くと、本体の `tsconfig.json`（`include: viewer-src/**/*`、`types: []`）と `.oxlintrc.json` の `viewer-src/**` override（`no-unsafe-*` を error）がテストにかかる。どちらも除外指定を足さないと成立しない。
- 隣接ディレクトリは site/ の `src/` と `test/` の分け方と同じ形。BefoldApp 直下はどの Swift ターゲットの path にも入らない（Package.swift の target path は CGitShim / BefoldCLI / BefoldPDFProbe / BefoldKit / BefoldRenderKit / befold ...、project.yml の sources も同じ）ので、`Package.swift` の `exclude: ["Resources/__tests__"]` と `project.yml` の `excludes: "__tests__/**"` が不要になる（viewer-src を BefoldApp 直下に置いた理由と同じ。viewer-src/README.md「なぜここに置くか」）。

採らなかった案:
- ソースと同居（`viewer-src/**/*.test.ts`）: 上記の対応関係が無く、tsconfig と oxlint override の両方に除外が要る。
- `BefoldKit/Resources/__tests__` のまま: テスト対象が Resources にあった頃の名残で、Swift ターゲット側の除外指定 2 つを残し続ける。
- `viewer-src/__tests__/`: 同居案と同じく tsconfig / oxlint の除外が要る。

ファイル名は変えない（`viewer-main-*.test` などの名前は衝突せず、改名は別の判断になる）。`support/` のサブディレクトリはそのまま持っていく。

## 決めた構成で変わるもの

| 対象 | 変化 |
|---|---|
| 本体 `tsconfig.json` | 変更なし（include は viewer-src のみのまま。types: [] を緩めない） |
| テスト用 tsconfig | 623.3 で `viewer-test/tsconfig.json` を新設（本体を extends し、jest / node の型と toSorted 用の lib を足す） |
| `.oxlintrc.json` | override の files `BefoldKit/Resources/__tests__/**` 2 箇所を `viewer-test/**` へ。`viewer-src/**` の no-unsafe-* override はテストにかからないまま |
| 循環検査 `check-viewer-cycles.mjs` | 変更なし（エントリ index.ts と viewer-src/ のグラフだけを見る） |
| esbuild のエントリ | 変更なし。テストハーネスの `VIEWER_SRC_DIR` / `RESOURCES_DIR` の相対パスだけ追随 |
| Jest 設定（package.json） | `testMatch` と `setupFiles` のパス |
| Package.swift / project.yml | テスト除外の指定を削除 |
| doc 引用検査 `check-doc-citations.sh` | 引用元の `docs/dev/rules/testing.md` を新パスへ。検査スクリプト自体はコメント中の例示だけ |
| その他の引用 | viewer-src/README.md、ViewerShortcutCatalog.swift の doc コメント、scripts/webview-smoke.swift のコメント、.claude/CLAUDE.md、BefoldApp/.oxlintrc.json のコメント |

スナップショット層（`docs/superpowers/**`、`backlog/**`）と ADR 0005 の Context（当時の `__tests__/` の実測）は当時の記述なので書き換えない。

## ADR の要否

作らない。どちらの判断も git mv と設定の追随で戻せる可逆な選択で、他の選択肢を潰すものではない。記録は本タスクの Notes と、現在仕様側の viewer-src/README.md「なぜここに置くか」へ置く（623.2 で追記）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-src はフラットのまま、テストは BefoldApp/viewer-test/ へ移すと決めた。根拠はテスト 16 本の require 実測（barrel 経由 15 本・個別モジュール 1 本で、モジュールとテストの 1:1 対応が無い）と、同居させると本体 tsconfig・oxlint override に除外が要ること。採らなかった案と各設定への影響は Notes に列挙。可逆な選択のため ADR は作らない（AC#3 は該当なしとして確認）。
<!-- SECTION:FINAL_SUMMARY:END -->
