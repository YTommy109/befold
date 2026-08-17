---
id: TASK-486
title: ビューアの上下スクロールがジャンプする（スムーススクロールにしたい）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-15 11:37'
updated_date: '2026-08-17 05:21'
labels:
  - bug
dependencies: []
priority: medium
type: bug
ordinal: 715500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ユーザー報告: ビューアで上下スクロールすると表示位置がジャンプし、スムーススクロールにならない。位置が飛ぶと読んでいた行を見失うため、滑らかにスクロールしてほしい。

要調査（起票時点では未特定）:

- どの操作で発生するか（キーボードのスクロール操作 / スクロールバー / トラックパッド等）
- どの表示モードで発生するか（Markdown レンダリング / ソース表示 / 差分表示 等）
- WKWebView 側のスクロール実装（viewer.html / CSS の scroll-behavior か、evaluateJavaScript による scrollTo か）のどこでジャンプが起きているか

着手時にまず再現条件をユーザーに確認するか実機で特定し、原因箇所を特定してから修正方針を決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 上下スクロール操作で表示位置が瞬間移動せず、滑らかにスクロールする
- [x] #2 再現条件（操作・表示モード）が Implementation Notes に記録されている
- [x] #3 スクロール以外の表示位置制御（検索ヒットへのジャンプ、ファイル再読込時の位置復元など）の挙動が変わっていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. スクロールに関わる実装（キーボード / CSS / チャンク追記 / 位置復元 / 検索ジャンプ）を網羅的に洗い出し、瞬間移動が起きる箇所を特定する。
2. 実 WKWebView のハーネスで scrollTop の時間推移を実測し、behavior:'auto' と 'smooth' の差、およびキーリピート相当の連打での取りこぼしを測る。
3. 落ちるテスト（jsdom で keydown を流し scrollBy の behavior を検証）を先に書く。
4. viewer-src/keyboard.ts の behavior を 'smooth' にし、viewer-bundle.js を再ビルドする。
5. 位置復元・検索ジャンプが変わっていないことを既存テスト一式で確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 再現条件（AC#2）

**操作**: ビューア内のキーボードスクロール — `Space` / `Shift+Space`（1 ページ）、`↑` `↓` / `j` `k`（1 行）、`Shift+↑↓`（半ページ）。配線は `viewer-src/keyboard.ts:76-131`（`_mmdInitKeyboard`）。

**表示モード**: モードに依存しない。スクロール対象は `_mmdScrollTarget()`（`viewer-src/scroll.ts:10-16`）が返す要素で、ソース／差分表示では `#diagram-wrap.code-body pre code`、それ以外（Markdown レンダリング・mmd・CSV・画像）では `.viewer`。どちらも同じハンドラを通る。

**トラックパッド・スクロールバーは対象外**: これらは WKWebView のネイティブ処理で、アプリ側のコードを通らない。Page Up/Down・Home/End も `resolveScrollKey` が null を返す（`keyboard.ts:44-58`）ためネイティブ処理に落ちる。

## 原因

`viewer-src/keyboard.ts:126` が `scrollEl.scrollBy({ top: ..., behavior: 'auto' })` を指定していた。'auto' は CSS の `scroll-behavior` が無い場合に瞬間移動になる。authored CSS 全体（style.css / github-markdown.css / github.css / github-dark.css）に `scroll-behavior` の指定は 0 件なので、常に瞬間移動していた。ページ単位のスクロールは移動量が clientHeight × 0.9 と大きく、飛び幅が最大になる。

git 履歴上、'auto' を意図して選んだ形跡は無い（`910de9d7` 以降の 3 件はいずれも移設・モジュール化のリファクタで、値はそのまま運ばれている）。backlog / ADR にも smooth を否定した判断は無い。

## 実測（実 WKWebView）

スクラッチパッドのハーネス（`scripts/webview-smoke.swift` と同じく実アプリの `loadFileURL(allowingReadAccessTo:)` 経路で viewer.html を読む）で、`.viewer`（clientHeight 600 / scrollHeight 16048）の scrollTop を requestAnimationFrame ごとにサンプリングした。

- `behavior:'auto'`: 最初のサンプルで既に 600 に到達。中間フレーム 0（= 瞬間移動）
- `behavior:'smooth'`: 0 → 600 を約 16 フレームかけて踏む（0, 0, 0, 32, 100, 181, 281, 360, 424, 473, 511, 541, 563, 578, 590, 597, 600…）
- キーリピート相当（30ms 間隔で 40px を 10 連打）: auto は 400px ちょうど、smooth は 385px。連打しても取りこぼさず、ずれは 1 ステップ未満

修正後、同じハーネスで**実際の keydown（Space）を同梱の viewer-bundle.js 経由**で流し、中間フレーム 15 回・0 → 540px（= 600 × PAGE_SCROLL_RATIO 0.9）を確認した。

## 単純化の検討（実装前）

CSS に `scroll-behavior: smooth` を置いて JS の behavior 指定自体を消す案を先に検討したが、**採らなかった**。CSS で指定すると `scrollTop` への代入まで animate されるため、ファイル切替・再描画時の位置復元（`viewer-src/scroll.ts:95-99` の `_mmdRestoreScrollPosition`、`render.ts:148`）が滑って着地しなくなり、AC#3 に反する。キーボード経路の 1 箇所だけを 'smooth' にするほうが、触る範囲も小さく副作用も無い。この判断はコード側のコメントにも残した。

## AC#3（他の表示位置制御が変わっていないこと）

変更は `keyboard.ts` の 1 行のみで、位置復元・検索ジャンプ・ズーム・ダイアグラム枠の高さ制御には触れていない。
- 検索ヒットへのジャンプ: `viewer-src/find.ts:344` は元から `behavior:'smooth'` で、変更なし
- 文書内アンカー: `viewer-src/reference-clicks.ts:65` も元から 'smooth' で、変更なし
- 位置復元: `viewer-src/scroll.ts:98` の `scrollTop` 代入（瞬時）のまま
- jest 453 件・swift 1603 件が通ることで回帰なしを確認

## 検証（実測）

- 新規テスト `viewer-main-keyboard-scroll.test.js`: 修正前は 8 件中 7 件が `Expected: "smooth" / Received: "auto"` で失敗、修正後は 8 件全通過
- `npm test`: 9 suites / **453 tests passed**
- `swift test`: **1603 tests in 254 suites passed**
- `npm run lint`（type-aware）/ `format:check` / `typecheck:viewer`: いずれも exit 0
- `scripts/webview-smoke.swift`: PASS
- markdownlint-cli2: 0 issues

## 再現条件のユーザー確認（2026-08-17）

報告された「上下スクロール」が**キーボード操作**であることをユーザーに確認済み。静的解析と実測から特定した経路（viewer-src/keyboard.ts の scrollBy）と一致するため、本修正で解消する。トラックパッド／スクロールバー経路の調査は不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ビューアのキーボードスクロール(Space / Shift+Space / ↑↓ / j k / Shift+↑↓)が behavior:'auto' で瞬間移動していたのを 'smooth' に変えた(viewer-src/keyboard.ts:126)。実 WKWebView のハーネスで、修正前は最初のフレームで目標位置へ到達し中間フレームが 0 だったのに対し、修正後は実際の keydown 経由で 0 → 540px を 15 フレームかけて踏むことを実測した。CSS の scroll-behavior は使わない(scrollTop への代入まで animate され位置復元が着地しなくなるため)。回帰は jest 453 件・swift 1603 件・webview-smoke で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
