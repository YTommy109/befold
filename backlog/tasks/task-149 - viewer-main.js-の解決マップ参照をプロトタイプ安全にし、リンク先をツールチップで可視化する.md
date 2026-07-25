---
id: TASK-149
title: viewer-main.js の解決マップ参照をプロトタイプ安全にし、リンク先をツールチップで可視化する
status: Done
assignee: []
created_date: '2026-07-25 11:31'
updated_date: '2026-07-25 12:10'
labels:
  - path-reference
  - security
dependencies: []
priority: medium
type: task
ordinal: 225000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
セキュリティレビュー指摘（低 L-1 / L-2）。(1) `_mmdApplyResolvedReferences` の `map[t.raw]`（viewer-main.js L304-315）が Object.prototype 継承値を拾うため、`constructor` 等をパス参照として書いた Markdown で未解決パスが befold-link 化される（偽リンク表示）。`uniq` への `__proto__` 代入も参照が静かに dead 扱いになる。(2) DOMPurify は class / data-* を許可するため、生 HTML の span で表示文字列と無関係な実在パスへ誘導する「解決済み風リンク」を作れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 解決マップの参照を Object.prototype.hasOwnProperty.call（または Map）で判定する
- [x] #2 uniq を Object.create(null) か Set にする
- [x] #3 dataset.resolved を title（ツールチップ）等で表示し、実際の遷移先を可視化する
- [x] #4 `constructor` / `__proto__` をパス参照に含む文書の Jest 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. viewer-main.js `_mmdApplyResolvedReferences`: `map[t.raw]` を `Object.prototype.hasOwnProperty.call(map, t.raw)` で自己所有プロパティのみ参照するようにする（constructor 等の継承値で偽リンク化されない）
2. viewer-main.js `_mmdResolveReferences`: `uniq = {}` を `Object.create(null)` にし、`__proto__` 等のパスが静かに落ちないようにする
3. `_mmdApplyResolvedReferences`: 解決済みは `title = abs`（実際の遷移先をツールチップで可視化・生 HTML 由来の偽 title を上書き）、解決失敗は title を除去する
4. Jest 回帰テスト追加（`constructor` / `__proto__` / `hasOwnProperty` をパス参照に含む文書、title 可視化）。追加テストが修正前コードで落ちることを git stash で確認する
5. `npx jest` 全パス確認 → JS/CSS のみの差分であることを確認してコミット
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装内容

- `_mmdApplyResolvedReferences`: `map[t.raw]` を `Object.prototype.hasOwnProperty.call(map, t.raw)` ガード付きに変更。`constructor` / `toString` / `hasOwnProperty` をパスとして書いた参照が継承値で解決済み扱い（偽リンク）にならない。
- `_mmdResolveReferences`: `uniq = {}` → `Object.create(null)`。`__proto__` というパスがプロトタイプ代入に吸われて解決要求から静かに落ちる問題を解消。
- `_mmdApplyResolvedReferences`: 解決済みは `title = 解決先絶対パス`（文書側/生 HTML 由来の偽 title を上書きし、実際の遷移先を可視化）、解決失敗は `title` を除去。CSS 変更は不要（ネイティブツールチップ）。

## 追加テスト（BefoldKit/Resources/__tests__/viewer-main.test.js）

1. `Object.prototype 由来の名前を書いた参照は解決済み扱いにならない`
2. `__proto__ という名前の参照も解決要求に含める`
3. `解決先の絶対パスを title に出し、解決失敗時は元の title を残さない`

## 修正前に落ちることの確認

viewer-main.js を修正する前（テストのみ追加した状態）で `npx jest __tests__/viewer-main.test.js -t <各テスト名>` を実行し、3 件すべてが FAIL することを確認済み。

- テスト1: `classList.contains('befold-link')` が Expected false / Received true（継承値でリンク化されていた）
- テスト2: 送信 paths が `['./doc.md']` のみで `__proto__` が欠落
- テスト3: title が `/repo/secret.md` ではなく偽装値 `README.md` のまま

## 検証

`cd BefoldApp && npx jest` → PASS (298) FAIL (0)（基準 295 + 追加 3）。
`git status --short` で差分が JS 2 ファイル（実装・テスト）のみであることを確認（*.swift・CSS の変更なし）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
viewer-main.js の解決結果マップ参照を hasOwnProperty ガード付きにし、参照収集の uniq を Object.create(null) 化した。あわせて解決先絶対パスを title 属性に出し、生 HTML によるリンク偽装を目視で確認できるようにした。constructor / __proto__ / hasOwnProperty をパス参照に含む Jest 回帰テスト 3 件を追加し、修正前コードで 3 件とも FAIL することを確認したうえで修正。npx jest は PASS 298 / FAIL 0。
<!-- SECTION:FINAL_SUMMARY:END -->
