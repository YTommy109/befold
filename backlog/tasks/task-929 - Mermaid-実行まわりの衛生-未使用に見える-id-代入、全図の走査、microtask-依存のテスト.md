---
id: TASK-929
title: 'Mermaid 実行まわりの衛生: 未使用に見える id 代入、全図の走査、microtask 依存のテスト'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T11:24:00Z'
updated_date: '2026-11-09T12:36:00Z'
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
- [x] #1 id の代入は、不要と確認できれば削除され、必要なら理由がコメントに残っている
- [x] #2 走査のコストについて図の数を変えた実測が Notes にあり、実害がある場合だけ改善されている
- [x] #3 検索のテストが microtask の回数に依存しない形で script タグを待つ
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. id の読み手と全図走査のコストを実測する
2. id の代入を消す（TASK-928 と同じループ）
3. 検索のテストを microtask の回数に依存しない形にする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
id の代入: 削除した。mermaid.min.js の runThrowsErrors は u.id をログにしか使わず、描画には自前の mermaid-<n> を使う（ソースで確認）。viewer-src と style.css に読み手なし（rg）。図 19 種の高さは修正前と同じ。

全図走査: 実害なしで変更しない。_mmdWrapDiagrams の走査は 図 5000 個で 0.12ms、10 万ノード + 図 1000 個で 0.06ms。セレクタ .mermaid:not([data-processed]) は同じ文書で 0.8ms。レビューの O(N²) は形としては正しいが、図 1 個の描画（22ms 以上）より桁で小さい。

別件の観測: 追記 1 回の時間は図の数とともに増える（図 2 個 9ms、51 個 23ms、101 個 42ms、201 個 89ms）。上の走査では説明できない。原因は未調査（図 200 個を 1 個ずつ追記する極端な条件で、タスクにはしていない）。測定中に setTimeout を使うと 1 回約 1000ms と出たが、図の数によらず一定で、MutationObserver で測ると消えるので、ハーネスのタイマー間引きと判断した。

テスト: viewer-main-find-highlight.test.ts は microtask 1 回ではなく setTimeout 0 で待つ形にした。

検証は TASK-928 と同じ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
id の代入を削除し（mermaid はログにしか使わない）、検索のテストを microtask の回数に依存しない形にした。全図走査は 10 万ノードの文書でも 1ms 未満で実害がないので変更していない。追記時間が図の数とともに増える点は走査以外が原因で、未調査のまま Notes に残した。
<!-- SECTION:FINAL_SUMMARY:END -->
