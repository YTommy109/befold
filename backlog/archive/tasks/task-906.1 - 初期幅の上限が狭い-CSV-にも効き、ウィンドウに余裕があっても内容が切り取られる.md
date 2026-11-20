---
id: TASK-906.1
title: 初期幅の上限が狭い CSV にも効き、ウィンドウに余裕があっても内容が切り取られる
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:55:00Z'
updated_date: '2026-11-07T03:03:00Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: medium
type: bug
ordinal: 867000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #748 の目的は幅の広い CSV の改善だが、360px の上限はすべての CSV に効く。2 列の CSV で 2 列目が長いと、右側が空いていても切り取られる。従来の仕様は「長い識別子も切らない」（#708）で、PR が方針を変えた。

方針はメンテナーの判断事項で、未決定。レビューでの提案は、全列の自然幅が表示領域に収まるなら上限をかけない形。他のサブタスクの切り取りの範囲に影響するので、最初に決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 全列が表示領域に収まる CSV の扱いが決まり、決定が docs/dev/file-type-display.md に書かれている
- [x] #2 決定した動作をテストが検証している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. initialWidths で列ごとの自然幅（ヘッダーと標本の最大）も測る
2. 全列が未確定で、自然幅の合計が .csv-scroll の内容幅に収まるなら、幅を決めずに返す。widths が空なので表は自動レイアウトのまま（新しい状態を足さない）
3. 収まらない場合は従来どおり 90 パーセンタイルと 40〜360px
4. テスト: 収まる場合に幅が付かない / 内容幅の境界（padding を引く）/ 収まらない場合の上限 / 追記後も切り取らない / 追記で列が増えて収まらなくなると上限へ移る
5. file-type-display.md と JSDoc を更新し、バンドルを再生成して実際の WebKit で確認する

/review-design: 項目 3（setWidth・印刷）、6（追記ごとの測定は列数の少ない表だけ）、7（jsdom にレイアウトが無いので WebKit で確認）を確認。他は該当なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: メンテナーの決定どおり、全列の自然幅が表示領域に収まるなら上限をかけない。

単純化: 新しい状態を足さず、収まる表には幅を設定しないだけにした。widths が空なら applyWidths は何もしないので、表は #748 より前の自動レイアウトのまま。追記された行も切り取られず、widths が空の間は追記と再描画のたびに判定し直す。

判定は標本の最大幅の合計と .csv-scroll の内容幅（padding を除く）の比較。分位点で判定すると外れ値が切り取られるため使わない。201 行目以降に長い値があっても判定は変わらず自動レイアウトのまま（#748 より前と同じく折り返す）。

検証: jest 737 件成功（追加 5 件）。判定を 4 通り壊して落ちることを確認（判定なし / padding を引かない / 分位点で判定 / 境界を < に変更）。lint・format・型検査は成功。実際の WebKit（viewer.html + style.css + バンドル、幅 1200px）で確認: 2 列の表は csv-sized なしで切り取り 0（表 715px、内容幅 1104px）、行を追記しても同じ、12 列の表は csv-sized で全列 360px。

Swift の変更なしのため Swift のテストと swiftlint は対象外。native-app-design.md への反映は不要（型の構成に変化なし。表示仕様は file-type-display.md を更新）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
全列の自然幅が表示領域に収まる CSV には列幅を設定せず、自動レイアウトのまま内容を切り取らないようにした。収まらない表の規則（90 パーセンタイル、40〜360px）は変えていない。

判定は initialWidths にあり、新しい状態は足していない。jest と実際の WebKit で確認した。

残るリスク: 収まらない表の切り取りは TASK-906.2 以降で扱う。
<!-- SECTION:FINAL_SUMMARY:END -->
