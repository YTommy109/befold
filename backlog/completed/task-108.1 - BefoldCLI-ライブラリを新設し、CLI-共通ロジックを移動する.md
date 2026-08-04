---
id: TASK-108.1
title: BefoldCLI ライブラリを新設し、CLI 共通ロジックを移動する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 09:17'
updated_date: '2026-07-23 10:04'
labels: []
dependencies: []
references:
  - docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md
parent_task_id: TASK-108
priority: high
ordinal: 97000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldCLI ライブラリターゲットを Package.swift に追加し、CLI 共通ロジック（CLIInstanceRouter 送信側、CLIOpenOptions、CLICheckCommand、CLIBookmarkCommand、CLIInstaller）を移動・分割する。notification 名やキー定数もここに配置し、GUI 側が import BefoldCLI で参照できるようにする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Package.swift に BefoldCLI ライブラリターゲットが定義されている
- [x] #2 CLIInstanceRouter の送信側 (runningInstance, forward, waitForAck, notification 名定数) が BefoldCLI に配置されている
- [x] #3 CLIOpenOptions が BefoldCLI に移動されている
- [x] #4 CLICheckCommand が CLISubcommandCommand.swift から分割され BefoldCLI に配置されている
- [x] #5 CLIBookmarkCommand が CLISubcommandCommand.swift から分割され BefoldCLI に配置されている
- [x] #6 CLIInstaller が BefoldCLI に移動されている
- [x] #7 swift build が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. BefoldCLI/ ディレクトリに以下を作成: CLIInstanceRouter送信側, CLIOpenOptions, CLICheckCommand(resolveFileToOpen をDI), CLIBookmarkCommand(addBookmark をDI), CLIInstaller, CLICommandResult, ShellQuoting
2. Package.swift に BefoldCLI ライブラリターゲット追加(BefoldKit 依存)、befold に BefoldCLI 依存追加
3. befold 側: CLIInstanceRouter を受信側のみに縮小(import BefoldCLI)、BefoldRootCommand から移動済み型を削除(import BefoldCLI)、CLISubcommandCommand/CLIInstaller/ShellQuoting を削除
4. viewerSortOrder を befold 側の extension に配置
5. swift build 確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
BefoldCLI ライブラリ新設完了。CLIOpenOptions, CLIInstanceRouter, CLICheckCommand, CLIBookmarkCommand, CLICommandResult, CLIInstaller, ShellQuoting, AppVersion を移動。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
BefoldCLI ライブラリターゲットを新設し、CLI 共通ロジック(CLIInstanceRouter, CLIOpenOptions/CLISortOrderOption, CLICheckCommand, CLIBookmarkCommand, CLIInstaller, CLICommandResult/CLICommandResultPrinter, ShellQuoting)を移動した。CLICheckCommand は resolveFileToOpen、CLIBookmarkCommand は addBookmark をクロージャ DI に変更し、befold app ターゲットの DirectoryLister/BookmarkStore への直接依存を断った。befold 側は import BefoldCLI で参照し、CLIInstanceRouter.swift は CLIOpenOptions の viewerSortOrder extension のみに縮小。全 570 テストパス。
<!-- SECTION:FINAL_SUMMARY:END -->
