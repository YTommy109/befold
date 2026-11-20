---
id: TASK-906
title: 'PR #748（幅の広い CSV/TSV の表示改善）のレビュー指摘を修正する'
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T02:55:00Z'
updated_date: '2026-11-07T04:15:00Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/pull/748
priority: high
type: bug
ordinal: 866000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
外部からの PR #748 を取り込み、レビューの指摘はこちらで追加修正する方針にした。この PR は全 CSV/TSV の初期列幅を内容から決めて切り取るので、データの誤読や印刷の欠けが起きる。指摘を修正してからリリースしたい。

指摘ごとにサブタスクへ分け、1 サブタスクを stacked PR の 1 層にする想定。

着手条件: PR #748 が main にマージされていること。fork の PR は同じリポジトリの積み重ねの土台にできない。main へのマージでリリースは出ない（release.yml はタグでのみ発火）ので、先にマージしても利用者には届かない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 すべてのサブタスクが Done である
- [x] #2 修正がすべて main に入るまで、PR #748 を含むリリースを出していない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手不可の理由: PR #748 が main へマージされていない。マージされれば着手できる。順序: 方針（幅の上限）→ 切り取りの目印 → 自動幅の測り直し、印刷と検索はその後。

TASK-906.1〜906.6 はすべて Done。PR は #752 を最下層とするスタック。完了条件の「修正がすべて main に入るまでリリースしない」はマージ後に確認して Done にする。

スタックを 2026-11-07 に main へ一括マージした（#752〜#757、atomic）。main の内容は最上層 a49d42b8 と一致。ビルド版のアプリを実際の CSV 5 種で確認し、全項目 OK とメンテナーが確認した（狭い表の全文表示、省略記号と数値の全桁、スクロールバー、印刷プレビュー、検索、追加読み込み、保存での測り直しと手動幅の保持）。

CI のハング: #756 の build-and-test (default) が 1 回 30 分のタイムアウトで打ち切られた（失敗 0 件、03:29:34 以降出力なし、未完了 20 スイート）。再実行で成功。原因は未特定で、調査タスクは起票していない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
外部 PR #748 のレビュー指摘 8 件を 6 サブタスクに分けて修正し、#752〜#757 を main へ一括マージした。#748 自体も先にマージ済み。

修正の範囲: 狭い CSV の切り取りをやめる、切り取りに省略記号を付けて数値の桁を欠かさない、自動の幅を再描画で測り直す、印刷と PDF で全文を出す、検索後にセルを元へ戻す、測定処理の整理。

実装中に見つけた問題も修正した: 測り直しによる再描画の悪化（10,000 行 3,300ms → 390ms）と、省略記号があると検索でスクロールできない問題。

残るリスク: CI のハングが 1 回あり原因は未特定。
<!-- SECTION:FINAL_SUMMARY:END -->
