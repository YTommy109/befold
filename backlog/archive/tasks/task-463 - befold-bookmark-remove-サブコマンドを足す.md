---
id: TASK-463
title: befold bookmark remove サブコマンドを足す
status: To Do
assignee: []
created_date: '2026-08-12 04:13'
labels: []
dependencies: []
priority: low
ordinal: 686000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI にはブックマークの add しか無く、削除は GUI からしかできない（issue #485 の対応で GUI 側は File Not Found アラートの「ブックマークから削除」と Bookmarks メニューの一括除去を用意した）。CLI からも同じ操作ができるようにする。BookmarkStore.remove / removeAll は実装済みで、CLIBookmarkCommand（BefoldApp/BefoldCLI/CLIBookmarkCommand.swift）に remove 経路を足す作業。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold bookmark remove <path> でブックマークが外れる
- [ ] #2 存在しないパスでも remove できる（add と違い fileExists で弾かない）
- [ ] #3 GUI と同じ UserDefaults 領域に反映されることを befoldCLITests で検証する
<!-- AC:END -->
