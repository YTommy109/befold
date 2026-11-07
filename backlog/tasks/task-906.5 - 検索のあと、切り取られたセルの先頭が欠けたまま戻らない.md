---
id: TASK-906.5
title: 検索のあと、切り取られたセルの先頭が欠けたまま戻らない
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:56:00Z'
updated_date: '2026-11-07T03:20:00Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: medium
type: bug
ordinal: 871000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
find-host.ts のスクロール処理は overflow: hidden の要素も対象にする（/^(auto|scroll|hidden)$/）ので、切り取られた部分にあるヒットへ移動すると td を内部でスクロールする。スクロールバーが無いのでユーザーは戻せず、再描画まで値の先頭が欠けて見える。

実測（WKWebView、自作の最小 HTML）: overflow: hidden の td で scrollTo が効き、scrollLeft=120 のまま残る。検索経由の動作そのものは未実測。

overflow: clip にするとセルは動かないが、ヒットが見えなくなる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 切り取られた部分にあるヒットへ移動すると、ヒットが見える
- [x] #2 別のヒットへ移動するか検索を閉じると、セルの表示位置が先頭へ戻る
- [x] #3 上記をテストまたは実機で確認した結果が Notes にある
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ヒットの所属セルが table.csv-sized の切り取りセルなら、移動の前に省略記号を外して内部スクロールを許す
2. 次のヒットへ移るとき（moveFindHighlight）とハイライトを消すとき（clearNativeHighlights、閉じる・再検索の共通経路）に元へ戻す
3. jsdom のテストと、実際の WebKit で確認する

/review-design: 項目 3（clearNativeHighlights は検索の全経路が通る）、7（スクロールは jsdom で動かないので WebKit で確認）。他は該当なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測で方針を修正: TASK-906.2 の省略記号があると、隠れた文字の Range の矩形が幅 0 に潰れて省略記号の位置で返る（hitLeft=408、hitW=0。clip なら hitLeft=1185、hitW=19）。このためスクロール量を計算できず、セルの内部スクロールそのものが起きない。jsdom のテストは通るので、実機で初めて分かった。ヒットのセルだけ移動の前に clip にする形へ変えた。判定をスクロール処理の中からヒットの所属セルへ移したので、処理も単純になった。

検証（WKWebView、150 文字目にヒットがある 3 セル）: 1 件目で scrollLeft [771,0,0] かつヒットがセル内、次のヒットで [0,771,0]、閉じると [0,0,0] で ellipsis に戻る。jest 752 件成功。切り取りを外さない / 移動で戻さない / 消去で戻さない の 3 通りを壊して落ちることを確認。lint・format・型検査・循環 import 検査は成功。

native-app-design.md への反映は不要（表示仕様は file-type-display.md を更新）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
検索で切り取られた部分のヒットへ移るとき、そのセルだけ省略記号を外して内部スクロールし、次のヒットへ移るときと検索を終えるときに元へ戻すようにした。

省略記号があると隠れた文字の矩形が潰れてスクロールできないことを実機で確認し、対応した。

残るリスク: ヒットでないセルをテキスト選択のドラッグで内部スクロールした場合は戻らない（検索の範囲外）。
<!-- SECTION:FINAL_SUMMARY:END -->
