---
id: TASK-1.3
title: viewer.html のブリッジ postMessage をガード付きヘルパーに一本化し、ホスト機能フラグを導入する
status: To Do
assignee: []
created_date: '2026-07-16 00:38'
updated_date: '2026-07-16 00:55'
labels: []
dependencies: []
references:
  - //github.com/YTommy109/befold/issues/211
parent_task_id: TASK-1
ordinal: 4000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GitHub Issue #211 から移行。referenceActivated の postMessage だけ存在ガードがなく、ハンドラ未登録の WebView で TypeError になる。5箇所の postMessage を一本化するヘルパーを導入し、Swift 注入のホスト機能フラグで Load More ボタン表示可否・Space キー処理を制御する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 postMessage が一箇所のヘルパー経由で呼ばれている
- [ ] #2 referenceActivated のガード未設定が解消されている
- [ ] #3 ホスト機能フラグで Load More ボタンの表示可否が制御できる
<!-- AC:END -->
