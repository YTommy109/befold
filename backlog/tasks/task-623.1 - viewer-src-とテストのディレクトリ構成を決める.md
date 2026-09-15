---
id: TASK-623.1
title: viewer-src とテストのディレクトリ構成を決める
status: To Do
assignee: []
created_date: '2026-09-14 11:57'
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
- [ ] #1 `viewer-src` の階層（フラットのまま / 関心ごとのサブディレクトリ）と、テストの置き場所（ソースと同居 / 隣接ディレクトリ）が、採らなかった案とその理由つきで記録されている
- [ ] #2 決めた構成で `tsconfig`・oxlint の override・循環検査・esbuild のエントリ・doc 引用検査がどう変わるかが列挙されている
- [ ] #3 不可逆な判断を含む場合は ADR（`backlog/decisions/`）として記録されている
<!-- AC:END -->
