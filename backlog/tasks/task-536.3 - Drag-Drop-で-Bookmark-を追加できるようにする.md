---
id: TASK-536.3
title: Drag & Drop で Bookmark を追加できるようにする
status: To Do
assignee: []
created_date: '2026-08-21 07:27'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-536
priority: medium
type: feature
ordinal: 779000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
本アプリには Drag & Drop の実装が現状どこにも無い（`NSDraggingDestination` / `draggingEntered` / `registerForDraggedTypes` / `performDragOperation` / SwiftUI `onDrop` のいずれも製品コードにヒット0件、実測）。前例のない状態からの新規実装になる。

Finder 等からファイル／フォルダをブックマーク管理 UI にドラッグ&ドロップすることで、そのパスをブックマークとして追加できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Finder からファイルをドラッグ&ドロップしてブックマークに追加できる
- [ ] #2 複数ファイルを同時にドラッグ&ドロップした場合、すべてがブックマークに追加される
- [ ] #3 既にブックマーク済みのパスをドロップした場合、重複登録されない
- [ ] #4 サポート対象外・存在しないパスがドロップされた場合、クラッシュせずユーザーに分かる形でフィードバックする
<!-- AC:END -->
