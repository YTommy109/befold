---
id: TASK-474
title: サイドバーのソート順を永続化する
status: To Do
assignee: []
created_date: '2026-08-13 11:31'
labels: []
dependencies: []
priority: low
ordinal: 695000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ソート順は現在 FileListModel.sortOrder 直書きでウィンドウごと・非永続。⋯ メニューへ移した(TASK-473)ことで設定らしい見た目になったが、再起動で既定へ戻る。UserDefaults へ永続化するなら、CLAUDE.md「UserDefaults キーの廃止・改名」の手順(移行経路を 1 本に畳む・defer での stale キー削除・3 ケースのテスト)に従うこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 サイドバーのソート順が再起動後も保たれる
- [ ] #2 全ウィンドウで同じソート順になるか、窓ごとに独立かの判断が Implementation Notes に記録されている
<!-- AC:END -->
