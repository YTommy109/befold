---
id: TASK-906.2
title: 切り取られた数値の末尾が目印なしで欠け、別の値に読める
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:56:00Z'
updated_date: '2026-11-07T03:08:00Z'
labels: []
dependencies:
  - TASK-906.1
references:
  - https://github.com/YTommy109/befold/pull/748
parent_task_id: TASK-906
priority: high
type: bug
ordinal: 868000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
初期幅は 90 パーセンタイルなので、幅の広い最大 1 割の値は最初から切り取られる。201 行目以降の値は標本に入らず、同様に切り取られることがある。text-overflow: clip なので目印が無い。

実測（WKWebView、自作の最小 HTML）: 幅 90px の右寄せセルに 1,234,567,890,123 を入れると、右寄せにならず左端から始まって右が切れ（textLeft=8、textRight=150.8、セル右端 98）、1,234,567, 付近までしか見えない。金額の列では最大の値ほど桁が欠け、小さい値に読める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 切り取られたセルは、切り取られていることが見た目で分かる
- [x] #2 `csv-num` の列では、初期幅の標本に含まれる値が切り取られない
- [x] #3 上記をテストが検証している
- [x] #4 `docs/dev/file-type-display.md` の「初期幅」「長い内容」が実装と一致している
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. style.css の csv-sized を text-overflow: ellipsis にする
2. initialWidths で td.csv-num の標本の最大幅を測り、その列の幅はこれを下回らせない。上限 360px の対象にもしない（標本の数値を切り取らないため）
3. テストと file-type-display.md、JSDoc を更新する
4. バンドルを再生成し、実際の WebKit の画面で省略記号と数値の全桁を確認する

/review-design: 項目 1（判定は描画済みの td.csv-num）、3（自動の幅は initialWidths のみ）、7（省略記号は描画で確認）を確認。他は該当なし
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化: 列の種類の判定は足さず、描画済みの td.csv-num の最大幅だけを見る。数値は上限 360px の対象から外した（完了条件のため）。オフセットの読み取りはセルごとに 1 回に保つ（既存テストが回数を守っている）。

検証: jest 成功。数値の幅の下限を外す変更と text-overflow: clip への変更で落ちることを確認。実際の WebKit の画面で省略記号を確認し、桁区切り付きの 16 桁の数値も切り取りなし（numClipped=0、Amount 列 167px）。lint・format・型検査は成功。

native-app-design.md への反映は不要（表示仕様は file-type-display.md を更新）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
切り取られたセルに省略記号を付け、数値の列は標本の最大幅を下回らないようにした。数値は上限 360px の対象から外した。

残るリスク: 201 行目以降の数値は切り取られることがあるが、省略記号で分かる。
<!-- SECTION:FINAL_SUMMARY:END -->
