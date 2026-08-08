---
id: TASK-315.2
title: unified diff をパースし、既存の code-table 構造でインライン差分を描画する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 14:46'
updated_date: '2026-08-05 15:15'
labels: []
dependencies:
  - TASK-315.1
parent_task_id: TASK-315
priority: medium
type: task
ordinal: 515000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-315 の 2 段目。左右分割は次段に回し、まず「1 列で追加・削除・文脈行を並べるインライン（line-by-line）表示」を JS 側に作る。

既存構造を再利用する:

- `viewer.js:334 renderCodeHtml` → `:324 wrapWithLineNumbers` → `:310 buildLineNumberRows` が、行番号 OFF のときも `<table class="code-table">` の 1 行 = 1 `<tr>` を生成する（インデントガイド `--indent-cols` / `--indent-depth` のため）
- ハイライトは `viewer.js:144 highlightCode`（hljs 11.11.1）と `reflowSpanBalancedLines`（行境界で `<span>` を閉じ直す）
- ソース表示の入口は `viewer-main.js:1657 _renderSource`

unified diff のパースは自前で書く（外部ライブラリを入れない方針は TASK-315 に記載）。テストは既存の jest 環境（`BefoldApp/BefoldKit/Resources/__tests__/`）で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 unified diff のパーサがハンク・行種別（追加/削除/文脈）・行番号を正しく返す（jest テストあり）
- [x] #2 インライン差分が既存の code-table 構造で描画され、行番号・インデントガイド・シンタックスハイライトが従来どおり効く
- [x] #3 追加・削除の行がライト/ダーク両テーマで区別できる
- [x] #4 差分が無い場合・パースに失敗した場合に、通常のソース表示へ安全に戻る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装（2026-08-06）

JS 側のみ。Swift 配線は下記のとおり TASK-315.3 へ移した。

- `viewer.js`: `parseUnifiedDiff(text)`（ファイル → ハンク → 行へ分解し、旧側・新側の行番号を各行に付ける）と `renderInlineDiffHtml(hljs, diffText, lang, showLineNumbers)` を追加。描画は既存の `lineContentCell` を通すため、インデントガイドの CSS 変数がそのまま付く。ハイライトは**ハンク単位でまとめて** hljs に渡す（1 行ずつだとブロックコメントや複数行文字列で字句状態が切れる）
- `viewer-main.js`: `setDiff(text)`（状態を持つだけ。再描画は Swift が直後に送る render に委ねる既存の作法に合わせた）と `_renderDiffHtmlIfAvailable()` を追加し、`_renderSource` と `_renderCode` の**両方**から呼ぶ
- `style.css`: `.diff-add` / `.diff-del` / `.diff-marker` / `.diff-hunk-header` と、ライト・ダーク両方の CSS 変数を追加。地色は半透明ティント（キャンバス色を書かない既存方針に従う）

## 設計上の判断

- **色だけに頼らない**: 行頭に `+` / `-` の記号セル（`.diff-marker`）を行番号の有無に関わらず必ず置く。背景色だけだと色覚特性やハイコントラスト設定で追加・削除を区別できない
- **CSV/TSV は対象外**: ソース表示が独自の列構造を持つため、差分表示に載せない
- **壊れた差分は通常表示へ**: `renderInlineDiffHtml` はハンクが 1 つも無ければ空文字列を返し、呼び出し側が通常のソース表示へ落ちる。例外も握って空文字列にする

## 検証

- jest 357 tests green（新規 21 件: `viewer-diff.test.js` 15 / `viewer-main-diff.test.js` 6）
- **テストが空振りしていないことの確認**: 実装途中、`_renderSource` にだけ差分分岐を足した状態で「差分が届いていれば差分表示になる」「setDiff(null) で解除できる」の 2 件が実際に落ちた。原因はコードファイルが `_renderCode` という別経路を通ることで、指摘どおり両方の入口へ差し込んで解消した（入口の列挙漏れ）
- **両テーマの見た目を実測**: 実 `style.css` を link した独立ハーネスで `takeSnapshot` し、ライト・ダーク両方で追加（緑）・削除（赤）・ハンクヘッダー・2 本のガター・+/- 記号が判別できることを画像で確認した
- `swift scripts/webview-smoke.swift`: PASS（CSP 下でのスクリプト稼働・描画・遮断）
- markdownlint-cli2: 0 件

## スコープの再配分（TASK-315.3 への申し送り）

当初 315.2 に含めていた Swift 側の配線（ViewerBridge の `setDiff` スクリプト、ViewerRenderer への受け渡し、ViewerStore と GitDiffLoader の接続、FeatureGate）は 315.3 へ移した。配線は差分表示の入口（トグル UI）と一体で設計しないと二度手間になるため。315.2 は「差分 HTML を組み立てる純粋な層と、JS 側の差し込み口」までを担当する。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
unified diff のパーサと、既存の code-table 構造へ載せるインライン差分描画を JS 側に実装した。ハイライトはハンク単位でまとめて hljs に渡し、行番号は旧側・新側の 2 本のガターに出す。色だけに頼らないよう +/- の記号セルを常に置く。差分が無い・パースできない場合は空文字列を返して通常のソース表示へ戻る。ソース表示の入口は _renderSource と _renderCode の 2 つあり、片方だけに足すと .swift で差分が出ない抜けになることを実際のテスト失敗で確認して両方へ差し込んだ。検証は jest 357 green（新規 21 件）、ライト・ダーク両テーマの実描画スナップショット、webview-smoke PASS。Swift 配線は TASK-315.3 へ移した。
<!-- SECTION:FINAL_SUMMARY:END -->
