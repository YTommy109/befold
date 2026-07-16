---
id: TASK-28.2
title: ツールバーボタンと View メニューでブックマークをトグルできるようにする
status: To Do
assignee: []
created_date: '2026-07-16 11:20'
updated_date: '2026-07-16 12:16'
labels: []
dependencies:
  - TASK-28.1
references:
  - docs/superpowers/specs/2026-07-16-bookmark-feature-design.md
parent_task_id: TASK-28
priority: low
ordinal: 132
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在開いているファイルのブックマーク状態をツールバーボタン（bookmark/bookmark.fill）と View メニュー項目で表示・トグルできるようにする。BookmarkStore に依存。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ツールバーボタンでブックマークの on/off を切り替えられ、状態がアイコン・contentTintColor に反映される
- [ ] #2 ファイル切り替え時にツールバーボタンの状態が新しいファイルの状態に更新される
- [ ] #3 View メニューにブックマークする/解除の項目があり、現在のファイルの状態に応じてタイトルが動的に切り替わる
- [ ] #4 キーボードショートカットが割り当てられ、既存ショートカットと衝突しない
<!-- AC:END -->
