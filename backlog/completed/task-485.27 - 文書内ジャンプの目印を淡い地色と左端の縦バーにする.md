---
id: TASK-485.27
title: 文書内ジャンプの目印を淡い地色と左端の縦バーにする
status: Done
assignee: []
created_date: '2026-09-25 08:10'
updated_date: '2026-09-25 08:58'
labels: []
dependencies: []
parent_task_id: TASK-485
ordinal: 828000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
見出し・定義ジャンプの目印が検索の <mark> と同じ装飾（候補は黄色地、現在位置はアクセントの青地に白文字）で目立ちすぎる。差分表示のような淡いパステル調の地色にし、現在位置は色を変えずに左端の濃い縦バーで示す。差分表示の変更ブロックのアクティブ表示（inset 3px の縦帯）と揃える。TASK-485.22 で決めた「検索と同じ装飾」を置き換える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 候補（非アクティブ）は淡いパステル調の地色で、文字色は変えない
- [x] #2 現在位置は地色を候補と同系に保ち、左端の濃い縦バーで示す
- [x] #3 差分表示の目印（縦帯・地色の打ち消し）は変わらない
- [x] #4 ライト・ダークの両方で色が定義されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
style.css の .mmd-jump-target / .mmd-jump-current を淡い地色（--jump-target-bg / --jump-current-bg）と、現在位置だけ左端 3px の縦バー（inset box-shadow, --accent）にする。表のセル以外は padding-left と同じ幅の負の margin で縦バーと文字の間を 8px 空け、文字位置は動かさない。差分表示の打ち消しは維持。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ユーザー指摘で縦バーと文字の間が詰まりすぎていたため 8px 空けた（表のセルは元から余白があるので対象外）。検証: アプリで Markdown の見出しジャンプを目視確認（ユーザー確認済み）。既存 JS テストはクラス付与だけを見るので CSS 変更の影響なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
文書内ジャンプの目印を、検索と同じ黄色地・青地白文字から、淡いパステル調の地色と左端の縦バーに変えた。差分表示のアクティブ表示と揃う。ライト・ダーク両方に色を定義。viewer-ui.md を更新。アプリで目視確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
