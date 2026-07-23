---
id: TASK-108.3
title: GUI 側の AppDelegate から CLI 分岐ロジックを除去する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 09:17'
updated_date: '2026-07-23 10:04'
labels: []
dependencies:
  - TASK-108.1
references:
  - docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md
parent_task_id: TASK-108
priority: high
ordinal: 99000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GUI バイナリ (befold) の AppDelegate から CLI 関連の分岐ロジックを削除し、起動フローを単純化する。BefoldRootCommand.swift、CLISubcommandCommand.swift、CLIOpenOptions.swift を GUI 側から削除し、CLIInstanceRouter.swift は受信側のみに縮小する。AppDelegate は常にセッション復元から起動する構成に変更する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 AppDelegate から static func main(), launch(withInitialPaths:options:), decideLaunchAction(), isTrivialActivateOnly(), launchAppAndForward() が削除されている
- [ ] #2 initialPaths, initialOptions プロパティが削除されている
- [ ] #3 applicationDidFinishLaunching でのパス有無分岐が消え、常にセッション復元
- [ ] #4 BefoldRootCommand.swift, CLISubcommandCommand.swift, CLIOpenOptions.swift が GUI 側から削除されている
- [ ] #5 GUI 側の CLIInstanceRouter.swift が受信側のみ (decode, sendAck, requestID) に縮小されている
- [ ] #6 GUI 側が import BefoldCLI で notification 名定数を参照している
- [ ] #7 swift build が通り、GUI アプリが正常に起動する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppDelegate から LaunchAction/decideLaunchAction/isTrivialActivateOnly/launch/launchAppAndForward/initialPaths/initialOptions を削除
2. init() を引数なしに単純化
3. static func main() を NSApplication 起動のみに単純化
4. applicationDidFinishLaunching を常にセッション復元に変更
5. BefoldRootCommand.swift を GUI 側から削除
6. AppDelegateLaunchTests の削除対象メソッドのテストを削除
7. swift build + テスト確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AppDelegate から CLI 分岐ロジック除去完了。LaunchAction/decideLaunchAction/isTrivialActivateOnly 削除、BefoldRootCommand.swift 削除。対応テストは TASK-108.6 で再構成予定。
<!-- SECTION:NOTES:END -->
