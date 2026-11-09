---
id: TASK-929
title: 'Mermaid 実行まわりの衛生: 未使用に見える id 代入、全図の走査、microtask 依存のテスト'
status: To Do
assignee: []
created_date: '2026-11-09T11:24:00Z'
labels:
  - viewer
dependencies:
  - TASK-926
references:
  - BefoldApp/viewer-src/mermaid.ts
  - BefoldApp/viewer-src/zoom.ts
  - BefoldApp/viewer-test/viewer-main-find-highlight.test.ts
priority: low
type: chore
ordinal: 894000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/code-review high` の指摘のうち、挙動の不具合ではないもの。前提タスクの修正で実行の入口が変わるので、その後に見直す。

- `el.id = 'mmd-' + i + '-' + Date.now()`（mermaid.ts）: viewer-src と style.css に読み手が見当たらない（rg で確認済み）。mermaid 側が使わないことは未検証。実行が重なると描画済みの図の id も書き換える
- `_mmdWrapDiagrams` は実行のたびに全 `.mermaid` を走査して Set を作る。図 N 個を N チャンクで追記すると全体で O(N²) になるという主張で、実害は未測定
- `viewer-main-find-highlight.test.ts` は script タグの出現までちょうど 1 microtask 待つ。内部の Promise チェーンが変わると、検索と無関係な TypeError で落ちる
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 id の代入は、不要と確認できれば削除され、必要なら理由がコメントに残っている
- [ ] #2 走査のコストについて図の数を変えた実測が Notes にあり、実害がある場合だけ改善されている
- [ ] #3 検索のテストが microtask の回数に依存しない形で script タグを待つ
<!-- AC:END -->
