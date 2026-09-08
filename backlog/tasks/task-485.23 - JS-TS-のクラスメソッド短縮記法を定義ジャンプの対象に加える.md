---
id: TASK-485.23
title: JS/TS のクラスメソッド短縮記法を定義ジャンプの対象に加える
status: Done
assignee: []
created_date: '2026-08-23 16:34'
updated_date: '2026-09-04 01:56'
labels:
  - jump
dependencies: []
parent_task_id: TASK-485
ordinal: 796000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-485.4（ADR 0011）で入れた定義ジャンプは、JS/TS のメソッド短縮記法（`foo() {`、`async foo() {`、`get foo() {`）を対象にしていない。`if (x) {` / `while (x) {` / `} catch (e) {` と行の形が同じで、除外語彙を抱えないと誤検出するため（`viewer-src/jump-providers.ts` の DEFINITION_PATTERNS のコメントに記録）。

クラスを使う TS コードでメソッドが 1 つも拾えないので、実用上の穴になっている。

## 検討の入口

hljs は JS/TS のメソッド短縮記法に `span.hljs-title.function_` を付ける（呼び出し側にも付くのが ADR 0011 でトークン方式を採らなかった理由だが、**正規表現で行の形を絞ったうえでトークンを併用する**なら区別できる可能性がある）。行末が `{` で終わることとの組み合わせも候補。

いずれにせよ ADR 0011 の「トークンは除外にだけ使う」を変えることになるので、変えるなら ADR を更新する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 クラスメソッド（通常・async・get/set）が定義として拾える
- [x] #2 if / while / for / switch / catch の行を定義と誤検出しないことを実 hljs 出力に対するテストで示している
- [x] #3 ADR 0011 の判断を変える場合は ADR 側も更新されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
`JS_DEFINITION` に代替を 1 つ足す形で実装した（行あたりの正規表現は言語ごと 1 本のまま）。

## 方式: 行の形 + 名前の位置の予約語を否定先読み

`(?:修飾子\s+)* \*? (?!予約語\b) 名前 (?:<ジェネリクス>)? \(引数\) (?::戻り値型)? \{` の形。
修飾子は public/private/protected/static/readonly/abstract/override/declare/async/get/set、
名前は `#` 始まり（private フィールド）も許す。

**ADR 0011 の決定（トークンは除外にだけ使う）は変えていない。** `span.hljs-title.function_` を
肯定判定に使う案も検討したが、行の形だけで呼び出しは既に落ちる（`)` の直後が `{` にならない）ため
追加の利得が小さく、判定の分かれ目を hljs の出力形式へ移すことになるので採らなかった。
ADR は「対象外にした」と書いていた Consequences の 1 項目だけを、採った方式の記述へ更新した。

## 分かれ目が予約語リストだけであることの担保

`} else {` のように `}` で始まる行は名前が行頭に来ないので先読み以前に外れ、
`describe('x', () => {` のようなコールバック渡しは `)` の直後が `{` でないので外れる。
残る `if (x) {` / `for (...) {` / `while (x) {` / `switch (k) {` / `catch (e) {` は**予約語リストだけ**が
分かれ目なので、そこにテストを置いた（実 highlight.js を通すハーネス）。

- 「TS のクラスメソッド短縮記法を拾う」: constructor / get / set / public async / static + ジェネリクス /
  ジェネレータ `*entries()` / private フィールド `#hidden()` の 8 件
- 「制御構文を定義として拾わない」: if / else if / else / for / while / switch / do / try / catch / finally
- 「コールバックを渡す呼び出し行を定義として拾わない」: describe / it / setTimeout

**修正を戻して落ちることを確認した**: 否定先読みを外すと「制御構文を定義として拾わない」だけが落ちる
（16 件中 1 件）。

実装前に `/review-design` のチェックリストを当て、項目 3（消費経路の全列挙）で「対象外」と書いた
箇所が 3 つ（jump-providers.ts のコメント 2 箇所・ADR 0011・このタスク）あることを洗い出して全部直した。

jest 633 件通過。oxlint / oxfmt / markdownlint も通した。
<!-- SECTION:NOTES:END -->
