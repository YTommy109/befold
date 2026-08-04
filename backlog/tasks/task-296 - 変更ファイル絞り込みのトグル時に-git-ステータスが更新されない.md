---
id: TASK-296
title: 変更ファイル絞り込みのトグル時に git ステータスが更新されない
status: To Do
assignee: []
created_date: '2026-08-04 14:46'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: medium
type: bug
ordinal: 494000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の検証済み指摘（CONFIRMED）。

TASK-291 で toggleChangedFilesOnly から refreshAllSidebars() を外し、syncDisplayPreferences()（Bool 2 つのミラーのみ）に置き換えた結果、トグル時に git ステータスの再取得が一切走らなくなった。作業ツリーの編集は .git/index を触らないため GitIndexWatch は発火せず、キーウィンドウのままなら windowDidBecomeKey も再発火しないので、古いスナップショットのまま絞り込みが適用される。

該当: BefoldApp/befold/App/ViewerWindowManager.swift:115
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ターミナルでファイルを編集/revert した直後にトグルしても、絞り込み結果が最新の git 状態を反映する
- [ ] #2 バックグラウンドウィンドウの絞り込みも古い git ステータスのまま取り残されない
- [ ] #3 TASK-291 の「トグルでサイドバー全体を再読み込みしない」性質は維持する（一覧の再列挙は行わない）
<!-- AC:END -->
