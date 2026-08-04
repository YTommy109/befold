---
id: TASK-108.2
title: befold-cli executable を新設する
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
ordinal: 98000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold-cli executable ターゲットを Package.swift に追加し、BefoldCLICommand (@main, ArgumentParser エントリポイント) と CLIAppLauncher (open -a + poll + forward + exit ロジック) を実装する。CLI は NSApplication.run() を呼ばず、ArgumentParser の commandName は "befold" のままにする。ProcessLaunching プロトコル + デフォルト引数で Process DI を最初から組み込む。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Package.swift に befold-cli executable ターゲットが定義されている
- [x] #2 BefoldCLICommand が @main で ArgumentParser エントリポイントとして動作する
- [x] #3 --check, --bookmark, --version, --help, paths 引数が正しくディスパッチされる
- [x] #4 CLIAppLauncher が open -a + poll + forward + exit のフローを実装している
- [x] #5 パスなし起動時に open -a befold.app で GUI を起動して exit する
- [x] #6 NSApplication.run() を呼ぶコードパスが存在しない
- [x] #7 ProcessLaunching プロトコル + デフォルト引数で DI が組み込まれている
- [x] #8 swift build で befold-cli がビルドできる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
befold-cli executable 新設完了。BefoldCLICommand, CLIAppLauncher, CLIBookmarkDefaults を実装。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
befold-cli executable ターゲットを Package.swift に追加。BefoldCLICommand(@main, ArgumentParser)と CLIAppLauncher(open -a + poll + forward + exit)を実装。ProcessLaunching プロトコルで DI 済み。AppVersion を BefoldCLI に移動し両バイナリで共有。CLIBookmarkDefaults で UserDefaults(suiteName:) 経由のブックマーク永続化を実装。swift build で befold-cli がビルドでき、全 570 テストパス。
<!-- SECTION:FINAL_SUMMARY:END -->
