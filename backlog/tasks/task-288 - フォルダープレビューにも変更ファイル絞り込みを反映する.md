---
id: TASK-288
title: フォルダープレビューにも変更ファイル絞り込みを反映する
status: To Do
assignee: []
created_date: '2026-08-04 07:28'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 478000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
code-review(high, 2026-08-04)。showChangedFilesOnly を読むのは FileListModel.visibleEntries だけで、フォルダープレビュー（ViewerContentView → FolderListingView）には sortOrder と showHiddenFiles しか渡っていない。そのため絞り込み ON でフォルダー行を選ぶと、サイドバーは変更ファイルだけ、隣のプレビュー面は未変更を含む全件、という 2 つの答えが 1 ウィンドウ内に並ぶ。

docs/superpowers/specs/2026-07-18-folder-preview-listing-design.md の『プレビュー一覧はサイドバーの表示設定に従う』という契約と矛盾する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 絞り込み ON のとき、フォルダープレビューの一覧もサイドバーと同じ内容になる
- [ ] #2 フォルダープレビューが参照する表示設定の受け渡しが 1 箇所にまとまり、次に設定が増えたとき同じ漏れが起きない形になる
- [ ] #3 サイドバーとプレビューの一致を検証するテストがある
<!-- AC:END -->
