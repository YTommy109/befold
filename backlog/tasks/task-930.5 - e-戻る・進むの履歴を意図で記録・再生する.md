---
id: TASK-930.5
title: (e) 戻る・進むの履歴を意図で記録・再生する
status: To Do
assignee: []
created_date: '2026-11-25T00:13:12Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 867000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 2。いまの履歴は、記録時点の PreviewTarget（サイドバーの状態から導いた値）を写している。行の着地待ちの間に記録すると、ファイルを選んだまま「フォルダー提示」として残る（#794 の調査で実測）。意図を記録し、再生時は意図を書いてからサイドバーを合わせる形にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 履歴エントリは記録時の意図を持ち、サイドバーの状態から導いた値を写さない
- [ ] #2 フォルダー一覧の履歴へ戻ったとき、別フォルダーへの移動を伴っても、一覧の着地を待たずに本文がその一覧になる
- [ ] #3 ファイルの履歴へ戻ったとき、PreviewTarget の遷移に .folder が現れないことをテストで確かめる
<!-- AC:END -->
