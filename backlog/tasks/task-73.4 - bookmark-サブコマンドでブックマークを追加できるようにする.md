---
id: TASK-73.4
title: bookmark サブコマンドでブックマークを追加できるようにする
status: To Do
assignee: []
created_date: '2026-07-19 09:11'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既存の BookmarkStore(App/BookmarkStore.swift、TASK-28 系で実装済み)を再利用し、
CLI から `befold bookmark add <path>` のようなサブコマンドでブックマークを
追加できるようにする。TASK-73.1 の引数パーサー基盤に依存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 befold bookmark add <path> でファイルまたはフォルダをブックマークに追加できる
- [ ] #2 存在しないパスを指定した場合はエラーメッセージを表示して終了する
- [ ] #3 追加したブックマークが GUI（File > Bookmarks サブメニュー等）から確認できる
- [ ] #4 既にブックマーク済みのパスを再度指定した場合の挙動が明確である（例: 冪等に成功する、または重複エラーを出す）
<!-- AC:END -->
