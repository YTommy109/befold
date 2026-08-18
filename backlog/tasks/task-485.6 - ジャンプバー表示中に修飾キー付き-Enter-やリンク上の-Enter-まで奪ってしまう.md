---
id: TASK-485.6
title: ジャンプバー表示中に修飾キー付き Enter やリンク上の Enter まで奪ってしまう
status: Done
assignee:
  - '@claude'
created_date: '2026-08-17 14:02'
updated_date: '2026-08-18 02:15'
labels: []
milestone: m-6
dependencies: []
parent_task_id: TASK-485
priority: medium
type: bug
ordinal: 740000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景（/code-review high の指摘、verdict: CONFIRMED）

`resolveJumpNavigationKey`（`viewer-src/keyboard.ts:89-100`）は key / openBar / shiftKey / isComposing / keyCode しか見ず、modifier キー（metaKey / ctrlKey / altKey）とイベントターゲットを無視する。document レベルのハンドラ（`keyboard.ts:109-117`）が preventDefault するため、ジャンプバーが開いている間は Cmd/Ctrl/Alt+Enter のチョードや、Tab でフォーカスしたリンク上の Enter（markdown-it の出力はタブ移動可能）まで「ジャンプ移動」として消費される。

find バーは Enter の処理を自分の input 要素の keydown リスナーにスコープしており（`viewer-src/find.ts:442-447`）、この問題を回避している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ジャンプバー表示中でも modifier 付き Enter（Cmd/Ctrl/Alt+Enter）は既定動作のまま通る
- [x] #2 フォーカスされたリンク上の Enter はリンクの既定動作になり、ジャンプ移動に消費されない
- [x] #3 素の Enter / Shift+Enter によるジャンプ前後移動は引き続き動く
- [x] #4 jest テストが上記の分岐を固定する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 単純化の検討（着手前）

引数を 2 つ足すと `resolveJumpNavigationKey` は 7 引数になる。代わりに、既に
すべてイベント由来のスカラ 5 個を **イベント形の 1 オブジェクトへ畳む**。
引数は 2 個へ減り、modifier の追加は追加コスト無しで収まる。

フォーカス判定は純粋関数に置かず、**スクロール側の既存ガードと同じ場所**
（ハンドラ内で `document.activeElement` を見る）へ揃える。DOM 参照をハンドラ側に
集める形が既に確立しているため、新しい経路を作らない。

ジャンプバー自身のボタンに対する例外は設けない。バーは開いた時点でフォーカスを
取らない（入力欄を持たない）ため通常の経路では activeElement は body であり、
Tab で明示的にボタンへ移った場合は Enter がそのボタンを押すのが正しい。

## 手順

1. `viewer-src/keyboard.ts` に `JumpNavigationKeyEvent` を定義し、
   `resolveJumpNavigationKey(e, openBar)` へ畳む。metaKey / ctrlKey / altKey が
   立っていれば null を返す。
2. 同ファイルに純粋関数 `ownsEnterKey(active: Element | null)` を足す。
   A[href] / BUTTON / INPUT / TEXTAREA / SELECT / contentEditable を true。
   mermaid の SVG リンクは SVGAElement で HTMLElement ではないため
   `instanceof HTMLElement` で絞らず tagName（小文字で来る）を大文字化して見る。
3. keydown ハンドラで `jumpDirection !== null && !ownsEnterKey(document.activeElement)`
   のときだけ preventDefault + ジャンプする。
4. jest テストを追加（`viewer-main-jump.test.js`）:
   Cmd/Ctrl/Alt+Enter で動かず defaultPrevented が false のまま /
   フォーカス中のリンク上の Enter で動かない / 素の Enter・Shift+Enter は動く。
   `ownsEnterKey` の分岐は `viewer.test.js` の純粋関数テストへ足す。
5. `npm run build:viewer` で `viewer-bundle.js` を更新（check:viewer-bundle が差分を見る）。
6. `npm test` / `npm run lint` / `npm run format:check` / `npm run typecheck:viewer`。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

`resolveJumpNavigationKey` の引数 5 個（すべて keydown 由来のスカラ）を
`JumpNavigationKeyEvent` 1 個へ畳み、metaKey / ctrlKey / altKey を追加した。
引数は 2 個へ減っている（修飾キーを個別引数で足すと 7 引数になり、呼び出し側で
順番を取り違えても型で気づけないため）。

フォーカス判定は純粋関数 `ownsEnterKey(active: Element | null)` に置き、
DOM を読むのは keydown ハンドラ側（スクロールの素通し判定と同じ場所・同じ形）。
対象は A[href] / BUTTON / INPUT / TEXTAREA / SELECT / contentEditable。
mermaid が出す SVG リンクは SVGAElement で HTMLElement ではないため
`instanceof HTMLElement` では絞らず tagName を大文字化して見る。

ジャンプバー自身のボタンへの例外は設けていない。バーは開いても入力欄を持たず
フォーカスを取らないので通常の経路では activeElement は body であり、Tab で
明示的にボタンへ移った場合は Enter がそのボタンを押すのが正しい挙動と判断した。

## 検証

- `npx jest viewer-main-jump.test.js`: 51 passed（新規 7 件）
- **修正を戻して落ちることを確認**: metaKey/ctrlKey/altKey のガードと
  `ownsEnterKey` 呼び出しを外すと新規 6 件が失敗（Cmd/Ctrl/Alt+Enter・リンク・
  ボタン・入力欄）。残る 1 件「href の無い <a>」は A を一律 true にすると失敗する
  ことを確認済みで、いずれも空振りしていない
- `npm test`: 517 passed / 10 suites
- `npm run typecheck:viewer` / `npm run lint`（--type-aware）/ `npm run format:check`: いずれも 0 件
- `npm run build:viewer` + `build:viewer-vendor` で viewer-bundle.js を更新
- `markdownlint-cli2`: 0 issues

## 残した制約

contenteditable の分岐は jest で固定していない。jsdom が `isContentEditable` を
実装しておらず（`contenteditable="true"` を付けても false）、テストを書いても
分岐を通らないため。テスト側にその旨をコメントで残した。実装側の判定は残してある
（スクロールの素通し判定と同じ理由）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ジャンプバー表示中の document レベル Enter が、Cmd/Ctrl/Alt 付きのチョードやフォーカス中のリンク・ボタン・入力欄の Enter まで消費していた問題を直した。resolveJumpNavigationKey をイベント形の 1 引数へ畳んで修飾キーを見るようにし、純粋関数 ownsEnterKey で「Enter を自分で処理する要素」にフォーカスがある間は譲るようにした。jest 7 件を追加し、修正を戻すと 6 件が落ちること・href の無い <a> のケースも空振りしないことを実測で確認した。npm test 517 passed、typecheck / lint / format はいずれも 0 件。現在仕様は docs/dev/native-app-design.md へ反映済み。
<!-- SECTION:FINAL_SUMMARY:END -->
