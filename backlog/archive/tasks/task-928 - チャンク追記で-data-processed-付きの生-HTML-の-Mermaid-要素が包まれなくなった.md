---
id: TASK-928
title: チャンク追記で data-processed 付きの生 HTML の Mermaid 要素が包まれなくなった
status: Done
assignee:
  - '@claude'
created_date: '2026-11-09T11:24:00Z'
updated_date: '2026-11-09T12:36:00Z'
labels:
  - bug
  - viewer
dependencies:
  - TASK-925
references:
  - BefoldApp/viewer-src/zoom.ts
  - BefoldApp/viewer-src/mermaid.ts
priority: low
type: bug
ordinal: 893000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`/code-review high` の指摘で、コードを読んだだけの未検証の主張。TASK-925 で `_mmdWrapDiagrams` の対象を渡された図に限定した。後続チャンクの生 HTML に `<div class="mermaid" data-processed="true">` があると、`.mermaid:not([data-processed])` に選ばれないので包まれない。修正前は別の図の実行が容器全体を走査するので、ズーム操作が付いていた。同じ記述が、最初の render では描画され、追記では描画されない。

実用上の文書にこの記述が現れるかは未確認で、現れないなら対応は不要の可能性がある。テストのフィクスチャはこの要素を含むが、包まれるかどうかを検証していない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 最初の render と追記で data-processed 付き要素の表示がどう違うかの実測が Notes に記録されている
- [x] #2 直す場合はチャンクによらず同じ扱いになり、修正を戻すと落ちる回帰テストがある。直さない場合はその根拠が Notes に記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. render と追記の差を修正前後のバンドルで実測する
2. render の data-processed 削除をやめ、_mmdRunMermaid の選択を未描画の図に一本化する
3. 両経路のテストを足し、戻して落ちることを確かめる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（2026-11-09、実 WKWebView + 実 mermaid、af91627c と 4b71eeb1 のバンドル）: data-processed 付きのソース文字列は render で描画され、追記では描画されない。描画済み SVG に data-processed を付けた図は、render で「No diagram type detected」のエラーになり、追記では正しく表示される。レビューの言う「TASK-925 で包まれなくなった」は、別の図と同じチャンクの場合だけで、修正前も包まれるのはソースのままの文字列にズーム操作が付くだけだった。単独の追記は修正前から包まれない。

単純化: 差の原因は render だけが data-processed を消すこと。消す処理は最初のコミット 074cb575 からあり理由の記録は無い。全形状が innerHTML で DOM を作り直す（renderers.ts）ので、属性が残るのは文書の生 HTML だけ。削除をやめて選択を一本化し、onlyUnprocessed の分岐を消した。

挙動の変更: data-processed 付きのソース文字列は render でも描画されず、文字列のまま表示する（追記と同じ。mermaid の属性の意味どおり）。描画済み SVG はエラーにならず表示する。どちらもズーム用に包まない。

修正後の実測（3 回同じ）: render と追記が 7 条件で一致、図 19 種の高さは修正前と同じ（gitGraph の差はランダムな ID の分）。テストを戻して確認: 削除を戻すと 2 件とも落ちる。

検証: Jest 769 件、typecheck / lint / format:check、swift test（--skip Integration --skip FileWatcherTests --skip PDF）1897 件 + 77 件が成功、known issue 1 件。docs/dev に data-processed の記述なし（rg で確認）で更新不要。実アプリでは未確認。

訂正: 上の「render と追記が 7 条件で一致」は不正確。測ったのは 7 シナリオで、比較した render と追記の組は 3 組（data-processed 付きソース文字列、属性なし、描画済み SVG）。この 3 組とも、図の表示とズーム用のラップ、エラーの有無が一致した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
生 HTML の data-processed 付きの図が、render と追記で違う結果になる問題を直した。描画済み SVG は render でエラーになっていた。原因は render だけが属性を消すことで、不要な処理だったので消し、選択を未描画の図に一本化した。data-processed 付きのソース文字列は render でも描画されなくなる。回帰テストは戻すと落ちることを確認済み。実アプリでは未確認。
<!-- SECTION:FINAL_SUMMARY:END -->
