---
id: TASK-73.2
title: 複数ファイル/フォルダ指定時に複数ウィンドウで開く
status: To Do
assignee: []
created_date: '2026-07-19 09:10'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI からファイルまたはフォルダを複数指定して起動した場合、それぞれ独立した
ウィンドウで開けるようにする。TASK-73.1 の引数パーサー基盤に依存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold file1.mmd file2.md のように複数ファイルを指定すると、ファイルごとに別ウィンドウが開く
- [ ] #2 befold folderA folderB のように複数フォルダを指定すると、フォルダごとに別ウィンドウが開く
- [ ] #3 ファイルとフォルダを混在指定した場合もそれぞれ別ウィンドウで開く
- [ ] #4 単一ファイル/フォルダ指定時の既存挙動が変わらない
<!-- AC:END -->
