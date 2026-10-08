---
id: TASK-684
title: TS 側のファイル・関数サイズ上限を oxlint で持つ（閾値を決めて有効化する）
status: To Do
assignee: []
created_date: '2026-10-08 09:34'
updated_date: '2026-10-08 09:35'
labels:
  - lint
  - site
  - viewer
dependencies: []
references:
  - .oxlintrc.json
  - site/.oxlintrc.json
  - BefoldApp/.oxlintrc.json
priority: medium
type: chore
ordinal: 873000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-498 で oxlint を導入したとき、`eslint/max-lines` / `eslint/max-lines-per-function` / `eslint/max-depth` / `import/max-dependencies` は **理由つきで off** にした。ルート `.oxlintrc.json` のコメントは「TS 側には行数の方針が無く、lint 導入に既存ファイルの分割判断を紛れ込ませない。必要なら独立したタスクで閾値ごと決める」と書いており、これがそのタスクである。

その時点で 957 行だった `site/src/analytics.ts` は 1726 行になり、`site/src/views/dashboard.tsx` も 1126 行ある。Swift 側は SwiftLint の `file_length`（warning 400）/ `type_body_length`（250）/ `function_body_length`（50）/ `cyclomatic_complexity`（10）が効いていて、超えたら `Type+Feature.swift` の extension へ分割する運用が定着している。TS 側だけ上限が無いので、同じ「超えたら分割する」運用を lint で持てるようにする。

## 実測（2026-10-08、oxlint 1.78.0、既定閾値）

`(cd site && npx oxlint -c .oxlintrc.json -D eslint/max-lines -D eslint/max-lines-per-function -D eslint/complexity -D eslint/max-depth -D import/max-dependencies)` と BefoldApp/ での同コマンド:

| 面 | max-lines(300) | max-lines-per-function(50) | complexity(20) | max-depth(4) | import/max-dependencies(10) |
|---|---|---|---|---|---|
| site/ | 11 ファイル | 56 | 0 | 0 | 1 |
| BefoldApp/ | 17 ファイル | 56 | 1 | 1 | 2 |

max-lines の超過ファイル（site/）: src/analytics.ts, src/lib/file-types.ts, src/routes/public.tsx, src/views/dashboard.tsx, src/views/features.tsx, src/views/landing.tsx, src/views/shared.tsx, test/analytics.test.ts, test/articles.test.ts, test/dashboard.test.ts, test/public.test.ts

max-lines の超過ファイル（BefoldApp/）: viewer-src/csv-html.ts, diff-html.ts, find.ts, jump-providers.ts, jump.ts, path-refs.ts, render.ts, renderers.ts, zoom.ts, viewer-test/viewer-csv-columns.test.ts, viewer-csv-resize.test.ts, viewer-diff.test.ts, viewer-main-bar-mode.test.ts, viewer-main-jump-function.test.ts, viewer-main-jump.test.ts（950 行）, viewer-main.test.ts（1574 行）, viewer.test.ts（1551 行）

28 件中 11 件がテストファイル。テストは describe 単位で読むので、本体と同じ閾値にするか・緩い閾値にするか・除外するかは判断が要る。既定の 300 は SwiftLint の 400 より厳しく、どちらに揃えるかも決める。

## 進め方の制約

有効化を error にすると、上記 28 ファイルを縮めるまで CI が落ちる。TASK-498/505 の前例どおり、**ルールは有効化し、超過ファイルは面ごとの override に実測件数と後続タスク ID をコメントに書いて一時除外する**。override が「直すべき指摘の置き場」に変わらないよう、除外した各ファイルには「除外を外しても通る」を AC に持つ後続タスクを付ける（analytics.ts と dashboard.tsx は起票済みでこのタスクに依存する。残りはこのタスクの中で一覧を Notes に残し、分割タスクを切るか閾値を見直すかを決める）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 max-lines / max-lines-per-function / max-depth / import/max-dependencies / complexity のそれぞれについて、閾値を「採用する値」または「採用しない理由」として決め、ルート .oxlintrc.json のコメントに実測件数つきで残す
- [ ] #2 テストファイル（site/test, viewer-test）の扱い（同じ閾値 / 緩い閾値 / 除外）を決めて設定に反映し、理由をコメントに書く
- [ ] #3 採用したルールは site/ と BefoldApp/ の両面で error として有効になり、`npm run lint` が両面で通る
- [ ] #4 現時点の超過ファイルは面ごとの override で理由・実測行数・後続タスク ID つきで一時除外し、除外一覧を Implementation Notes に残す
- [ ] #5 analytics.ts / dashboard.tsx 以外の超過ファイルについて、分割タスクを起票するか閾値を見直すかを決めて Notes に記録する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
後続（このタスクの override 一時除外を外す側）: TASK-685 analytics.ts、TASK-686 views/dashboard.tsx。
<!-- SECTION:NOTES:END -->
