---
id: TASK-505
title: 配布サイト（site/）に oxlint の type-aware linting を導入する
status: In Progress
assignee: []
created_date: '2026-08-16 11:53'
updated_date: '2026-08-16 12:00'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 736000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`site/` は Cloudflare Workers 上で動くため、await し忘れた D1 書き込みは実行前にリクエストが終わって黙って消える。この誤りは tsc でも型情報を使わない現行 oxlint でも検出できない。oxc の type-aware linting（`oxlint --type-aware` + `oxlint-tsgolint`）を site/ に導入し、`no-floating-promises` などの型情報が要るルールをゲートにする。

実測（2026-08-16、oxlint 1.78.0）:
- site/ 全体で既定の type-aware ルールセットは 567 件。内訳は `prefer-readonly-parameter-types` 250 /`no-deprecated` 160（大半が test/ の vitest-pool-workers `env`）/ `no-unsafe-*` 98 / `return-await` 13 / その他 46。
- ノイズ 2 ルールと test・tools・public を除くと src/ の指摘は 26 件（ほぼ `no-unsafe-type-assertion`）。
- `no-floating-promises` の検出は **0 件**。合成ファイルで検知が働くことは確認済み。つまり現状クリーンなまま回帰だけを止めるゲートとして入れられる。
- BefoldApp/ は 5,263 件（`no-unsafe-call` 2,667 ほか）。tsconfig の `checkJs: false` で viewer-src の大半が .js のままであることが原因なので、TASK-499 の完了までは導入しない。この判断は本タスクのスコープ外とする。

既存の指摘 26 件を潰す作業（`as` キャストを型ガードへ書き換える等）は本タスクに含めない。lint 導入に別の設計判断を紛れ込ませないという `.oxlintrc.json` 冒頭の既存方針に従う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 site/package.json の devDependencies に oxlint-tsgolint が入り、`npm run lint` が `--type-aware` 付きで動く
- [x] #2 typescript/no-floating-promises・no-misused-promises・await-thenable が error で有効になっている
- [x] #3 prefer-readonly-parameter-types と no-deprecated は理由コメント付きで off になっている（既存の無効化と同じ書式）
- [x] #4 site/ で `npm run lint` が 0 件で通る（既存 26 件を鳴らすルールは有効化しない）
- [x] #5 no-floating-promises が実際に検知することを、合成コードを一時的に置いて確認した記録が Implementation Notes にある
- [ ] #6 CI（site.yml）で type-aware lint が走り、導入前後の実行時間を実測して Notes に残している
- [x] #7 BefoldApp/ へ導入しない理由（実測 5,263 件・TASK-499 待ち）が TASK-499 の Acceptance Criteria か Notes に申し送られている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. site/package.json に oxlint-tsgolint を devDependency として追加し、lint / lint:fix を --type-aware 付きにする
2. site/.oxlintrc.json に type-aware ルールを追記する。有効化: no-floating-promises / no-misused-promises / await-thenable。無効化（理由コメント付き）: prefer-readonly-parameter-types / no-deprecated、および既存 26 件を鳴らす no-unsafe-type-assertion / return-await / no-confusing-void-expression ほか
3. npm run lint が 0 件で通ることを実測する
4. 合成コードで no-floating-promises が実際に鳴ることを確認する（確認後に削除）
5. .github/workflows/site.yml の lint 実行時間を導入前後で実測する
6. TASK-499 の Acceptance Criteria に「BefoldApp への type-aware 導入判断」を申し送る
7. .claude/CLAUDE.md の JS/TS コーディング規約に type-aware の扱いを 1 段落追記する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装内容

- `site/package.json`: devDependency に `oxlint-tsgolint@^7.0.2001` を追加し、`lint` / `lint:fix` を `--type-aware` 付きにした。package-lock には linux-x64 を含む 6 プラットフォーム分の optional binary が入っているので、ubuntu ランナーの `npm ci` でも実体が入る（実測: lock の `@oxlint-tsgolint/linux-x64` を確認）。
- `site/.oxlintrc.json`: 型情報を使うルールの節を新設。有効化 3 件 / 無効化 17 件（すべて理由コメント付き、既存の無効化と同じ書式）。
- `scripts/oxc-lint.sh`: pre-commit のスキップ判定に `site/node_modules/.bin/tsgolint` の有無を追加。無いまま呼ぶと "Failed to find tsgolint executable" で落ち、依存不足だと分からないため。
- `.github/workflows/site.yml`: lint ステップ名と実測コメントのみ。`npm run lint` を呼んでいるのでコマンド変更は不要。
- `.claude/CLAUDE.md`: JS/TS 規約に type-aware の扱いと BefoldApp へ入れない理由を追記。

## 検証

- `npm run lint` = 0 件・exit 0、`format:check` 0 件、`npm run typecheck` exit 0、`npm test` 347 passed / 12 files。
- **3 ルールが実際に検知することを合成コードで確認した**（確認後に削除）:
  - `no-floating-promises`: `src/__ta_probe.ts` で `work()` を await せず呼ぶ → `error typescript(no-floating-promises)`、exit 1。
  - `no-misused-promises`: `if (work())` → `error typescript(no-misused-promises): Expected non-Promise value in a boolean conditional.`
  - `await-thenable`: `await 42` → `error typescript(await-thenable)`。
  - 無効化側も確認: 導入前に 31 件出ていた `public/carousel.js` が exit 0 になった。
- 既知の限界: `no-misused-promises` の void-return 検査（`el.addEventListener("click", asyncFn)`）は tsgolint 7.0.2001 では発火しなかった。条件式の誤用は検知する。
- 実行時間（ローカル、3 回ずつ）: 型情報なし 0.49 / 0.49 / 0.51s → type-aware 0.68 / 0.69 / 0.72s。+0.2s。CI 上の実測は本 PR の site.yml 実行で確認する（AC #6 はローカル実測で判断した）。
<!-- SECTION:NOTES:END -->
