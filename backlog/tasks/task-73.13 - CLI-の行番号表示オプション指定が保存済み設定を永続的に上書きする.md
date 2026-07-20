---
id: TASK-73.13
title: CLI の行番号表示オプション指定が保存済み設定を永続的に上書きする
status: To Do
assignee: []
created_date: '2026-07-20 13:30'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/ViewerWindowController.swift:110'
  - 'BefoldApp/befold/Viewer/ViewerStore.swift:118-122'
parent_task_id: TASK-73
priority: medium
type: bug
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowController 初期化時、CLI の --line-numbers/--no-line-numbers オーバーライドは store.showLineNumbers に直接代入している。ViewerStore.showLineNumbers には didSet で UserDefaults へ書き込む副作用があるため、1回のCLI起動時オーバーライドがユーザーの保存済みグローバル設定を恒久的に上書きしてしまう。隣接する --source/--preview のオーバーライド(sourceModeOverride)は明示的に保存値を書き換えない実装になっており、意図とも矛盾している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLIからの --line-numbers/--no-line-numbers 指定は、その起動セッション限りの表示に反映され、UserDefaultsに保存されたグローバル設定を書き換えないこと
- [ ] #2 回帰テストを追加する
<!-- AC:END -->
