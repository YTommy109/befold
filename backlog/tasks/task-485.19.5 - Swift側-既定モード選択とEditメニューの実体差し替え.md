---
id: TASK-485.19.5
title: 'Swift側: 既定モード選択とEditメニューの実体差し替え'
status: To Do
assignee: []
created_date: '2026-08-21 09:12'
labels: []
dependencies:
  - TASK-485.19.3
  - TASK-485.19.4
parent_task_id: TASK-485.19
priority: high
ordinal: 779000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
WebViewCommandController に openBar(kind: DocumentJumpKind?) 相当の単一入口を作る。

- kind が nil（⌘F 相当の非明示オープン）のときだけ showsDiff を見て
  既定を search / changeBlock に分岐する
- kind 明示時（Edit > 見出しへジャンプ / 変更箇所へジャンプ）は常にそのモードを強制する
  （ユーザー承認済み方針: 現行の2メニュー項目は残し、実体だけ統合バーの該当モードへの
  切替えに差し替える）
- documentJump(_:)（ViewerWindowController+MenuActions.swift:60-63）と
  openFind()（WebViewCommandController.swift:96-98）をこの入口へ収斂させる
- ViewerWindowController / MainMenuBuilder 型グループの行数増分を確認する
  （実測: ViewerWindowController群896行/閾値1000、MainMenuBuilder群377行。
  scripts/check-type-group-size.sh で増分後も確認する）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ⌘Fで開いたとき、差分表示モードでは変更箇所モードが既定で選ばれる
- [ ] #2 Edit > 見出しへジャンプ / 変更箇所へジャンプ は常に明示したモードで開く
- [ ] #3 openFind() と documentJump(_:) が単一の入口関数に収斂している
- [ ] #4 ViewerWindowController / MainMenuBuilder 型グループが閾値を超えていない（超える場合は受け皿を決めている）
<!-- AC:END -->
