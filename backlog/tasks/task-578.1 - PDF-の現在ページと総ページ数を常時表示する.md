---
id: TASK-578.1
title: PDF の現在ページと総ページ数を常時表示する
status: To Do
assignee: []
created_date: '2026-08-30 11:57'
labels: []
dependencies: []
parent_task_id: TASK-578
priority: medium
ordinal: 841000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF 表示中、現在表示しているページ番号と総ページ数（例: 12 / 248）を画面上に常に表示する。連続スクロールでは 1 ページが画面をまたぐため、「現在ページ」の定義（表示領域の中心にあるページ等）を先に決めること。

配色の要件はユーザーからの指示: 常時表示になるので、でしゃばらない配色にしつつ読みやすさは保つ。ライト/ダーク両方で確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 PDF 表示中、現在ページ番号と総ページ数が常時表示される
- [ ] #2 連続スクロール中にスクロールすると表示中のページ番号が追随して更新される
- [ ] #3 回転・ズーム・ファイル切り替えの後も表示が正しい値になる
- [ ] #4 常時表示に耐える控えめな配色で、ライト/ダークの両方で読める
- [ ] #5 PDF 以外の表示面（web 面）では表示されない
<!-- AC:END -->
