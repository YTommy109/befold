---
id: TASK-578
title: PDF のページ位置表示とページ番号指定ジャンプ
status: Done
assignee: []
created_date: '2026-08-30 11:57'
updated_date: '2026-08-30 14:14'
labels: []
dependencies: []
priority: medium
ordinal: 840000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PDF 表示中に「現在ページ / 総ページ数」を常時わかるようにし、その表示から任意ページへ直接ジャンプできるようにする。連続スクロール表示になった今、いま何ページ目を見ているのかが画面から読み取れず、長い PDF で位置を見失う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 PDF 表示中は現在ページと総ページ数が常時見える
- [x] #2 その表示からページ番号を指定して当該ページへジャンプできる
<!-- AC:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サブタスク 578.1（常時表示）と 578.2（クリックしてページ番号でジャンプ）を完了した。PDF 面の左下に「現在ページ / 総ページ数」が常時出て、クリックすると数字入力へ変わり任意ページへ飛べる。両方とも実機で確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
