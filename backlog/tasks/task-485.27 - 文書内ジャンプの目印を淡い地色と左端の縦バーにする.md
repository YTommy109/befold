---
id: TASK-485.27
title: 文書内ジャンプの目印を淡い地色と左端の縦バーにする
status: To Do
assignee: []
created_date: '2026-09-25 08:10'
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
- [ ] #1 候補（非アクティブ）は淡いパステル調の地色で、文字色は変えない
- [ ] #2 現在位置は地色を候補と同系に保ち、左端の濃い縦バーで示す
- [ ] #3 差分表示の目印（縦帯・地色の打ち消し）は変わらない
- [ ] #4 ライト・ダークの両方で色が定義されている
<!-- AC:END -->
