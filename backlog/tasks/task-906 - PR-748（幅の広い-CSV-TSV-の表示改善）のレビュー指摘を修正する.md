---
id: TASK-906
title: 'PR #748（幅の広い CSV/TSV の表示改善）のレビュー指摘を修正する'
status: In Progress
assignee:
  - '@claude'
created_date: '2026-11-07T02:55:00Z'
updated_date: '2026-11-07T03:22:00Z'
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
- [ ] #1 すべてのサブタスクが Done である
- [ ] #2 修正がすべて main に入るまで、PR #748 を含むリリースを出していない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着手不可の理由: PR #748 が main へマージされていない。マージされれば着手できる。順序: 方針（幅の上限）→ 切り取りの目印 → 自動幅の測り直し、印刷と検索はその後。

TASK-906.1〜906.6 はすべて Done。PR は #752 を最下層とするスタック。完了条件の「修正がすべて main に入るまでリリースしない」はマージ後に確認して Done にする。
<!-- SECTION:NOTES:END -->
