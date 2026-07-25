---
id: TASK-135
title: 同名 CLIInstanceRouter.swift の解消と GUI 側境界アダプタを実態に合わせて改名する
status: To Do
assignee: []
created_date: '2026-07-24 22:40'
updated_date: '2026-07-25 00:25'
labels:
  - refactor
  - structural
  - cli
dependencies: []
priority: high
ordinal: 50000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold/App/CLIInstanceRouter.swift は全 8 行で、中身は extension CLIOpenOptions の viewerSortOrder(CLIオプション→Viewer 層 SortOrder 変換)だけであり CLIInstanceRouter 型は存在しない。本物のルーターは BefoldCLI/CLIInstanceRouter.swift。同名 2 ファイルが grep/ナビゲーションを紛らわしくし、GUI 側ファイル名が内容(境界変換アダプタ)と一致していない。構造レビュー(2026-07-25)で検出。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GUI 側ファイルが内容に合う名前(例: CLIOpenOptions+ViewerSortOrder.swift)へ改名され、同名 2 ファイルが解消している
- [ ] #2 project.yml / Package.swift のソース参照とビルドが更新後も通る
<!-- AC:END -->
