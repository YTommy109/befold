---
id: TASK-578.2
title: ページ数表示をクリックしてページ番号指定でジャンプできるようにする
status: To Do
assignee: []
created_date: '2026-08-30 11:57'
labels: []
dependencies:
  - TASK-578.1
parent_task_id: TASK-578
priority: medium
ordinal: 842000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ページ位置表示をクリックすると、その場が数字入力エリアに変わり、入力したページ番号へジャンプする。入力を確定/取り消した後は通常の表示に戻る。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ページ数表示をクリックすると数字入力エリアに切り替わる
- [ ] #2 ページ番号を入力して確定すると当該ページへジャンプする
- [ ] #3 範囲外・非数値の入力ではジャンプせず、表示が壊れない
- [ ] #4 Esc など取り消し操作で入力を破棄して通常表示へ戻る
- [ ] #5 確定/取り消しの後、現在ページ表示が実際の表示位置と一致する
<!-- AC:END -->
