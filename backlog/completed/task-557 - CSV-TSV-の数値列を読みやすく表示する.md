---
id: TASK-557
title: CSV/TSV の数値列を読みやすく表示する
status: Done
assignee: []
created_date: '2026-08-27 04:18'
updated_date: '2026-08-27 05:27'
labels: []
dependencies: []
ordinal: 805000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CSV/TSV のテーブル表示で、数値の列を右寄せし、量を表す列には桁区切りを入れ、会計用途向けに負の数の表現を選べるようにする。

現状 `viewer-src/csv-html.ts` の `csvRowsHtml` はセルを `escapeHtml` してそのまま `<td>` に入れるだけで、型判定・整形は Swift 側にも TS 側にも存在しない。桁の揃わない数値列は読み取りづらい。

befold はオープンソースで配布先のユーザー層が不明なため、判定は「当たれば嬉しい」ではなく「外さない」を優先する。郵便番号や商品コードに桁区切りを入れる誤りは、金額に桁区切りが入らない取りこぼしよりはるかに悪い。逃げ道としてソース表示（⌘2 の `csv-source`）が無加工の原文を見せているので、per-file の設定と永続化は今回作らない。

サブタスクに分割する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 数値列が右寄せかつ桁が揃って表示される
- [x] #2 コードとみなせる列（郵便番号・商品コード・年・行番号など）に桁区切りが入らない
- [x] #3 負の数の表現を Preferences から切り替えられる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
サブタスク 2 件（TASK-557.1 / TASK-557.2）で実装し、どちらも Done。

- #1 右寄せ・桁揃え: 列判定の第 1 段（非空セルがすべて数値）を満たす列に `csv-num`（`text-align: right` + `font-variant-numeric: tabular-nums`）を付ける。557.1 で実装。
- #2 コード列に桁区切りを入れない: 第 2 段の 6 つの拒否条件（1,000 以上が無い / 先頭ゼロ / 固定長 / 年 / 行番号 / ヘッダー否定語）。条件ごとの検証はテストが reason を突き合わせる。557.1 で実装。
- #3 負の数の表現を Preferences から切り替え: 通常 / ▲ / 赤字 / ▲+赤字。桁区切りのオン/オフも同じ Section に置いた。557.2 で実装。

**肯定側のヘッダー名マッチ（price / 金額 等）は最後まで使っていない。** 網羅不能で誤爆を増やす方向にしか働かないため。会計慣習の ▲・赤字は「どの列が金額か」を推測せず、設定そのものが意図を運ぶ設計にした（既定を通常表記にしておけば、変えるユーザーは自分のファイルが会計データだと宣言している）。

実装後に判明した弱点は 557.1 の Notes に記録済み（1,000〜9,999 に収まる金額列は固定長条件で桁区切りが入らない／⌘F の本文検索が桁区切りに当たらない）。逃げ道はどちらもソース表示（⌘2）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CSV/TSV のテーブル表示で、数値列を右寄せ + tabular-nums にし、コードとみなせない量の列にだけ桁区切りを入れるようにした。判定は「外さない」を優先した二段構えで、肯定側のヘッダー名マッチは使わない。桁区切りの有無と負の数の表記（通常 / ▲ / 赤字 / ▲+赤字）は app-global の Preferences から切り替えられ、開いている全窓へ即時反映される。検証は swift test 1712 件・jest 630 件の全通し、swiftlint ベースライン差分ゼロ、型グループ検査 exit 0。
<!-- SECTION:FINAL_SUMMARY:END -->
