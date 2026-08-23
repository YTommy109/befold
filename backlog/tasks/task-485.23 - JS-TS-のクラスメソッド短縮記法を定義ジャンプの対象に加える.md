---
id: TASK-485.23
title: JS/TS のクラスメソッド短縮記法を定義ジャンプの対象に加える
status: To Do
assignee: []
created_date: '2026-08-23 16:34'
labels:
  - jump
dependencies: []
parent_task_id: TASK-485
ordinal: 796000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-485.4（ADR 0009）で入れた定義ジャンプは、JS/TS のメソッド短縮記法（`foo() {`、`async foo() {`、`get foo() {`）を対象にしていない。`if (x) {` / `while (x) {` / `} catch (e) {` と行の形が同じで、除外語彙を抱えないと誤検出するため（`viewer-src/jump-providers.ts` の DEFINITION_PATTERNS のコメントに記録）。

クラスを使う TS コードでメソッドが 1 つも拾えないので、実用上の穴になっている。

## 検討の入口

hljs は JS/TS のメソッド短縮記法に `span.hljs-title.function_` を付ける（呼び出し側にも付くのが ADR 0009 でトークン方式を採らなかった理由だが、**正規表現で行の形を絞ったうえでトークンを併用する**なら区別できる可能性がある）。行末が `{` で終わることとの組み合わせも候補。

いずれにせよ ADR 0009 の「トークンは除外にだけ使う」を変えることになるので、変えるなら ADR を更新する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 クラスメソッド（通常・async・get/set）が定義として拾える
- [ ] #2 if / while / for / switch / catch の行を定義と誤検出しないことを実 hljs 出力に対するテストで示している
- [ ] #3 ADR 0009 の判断を変える場合は ADR 側も更新されている
<!-- AC:END -->
