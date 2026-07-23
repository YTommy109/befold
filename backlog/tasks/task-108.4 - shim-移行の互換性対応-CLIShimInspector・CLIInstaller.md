---
id: TASK-108.4
title: shim 移行の互換性対応 (CLIShimInspector・CLIInstaller)
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 09:18'
updated_date: '2026-07-23 10:14'
labels: []
dependencies:
  - TASK-108.2
references:
  - docs/superpowers/specs/2026-07-23-cli-binary-separation-design.md
parent_task_id: TASK-108
priority: high
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIInstaller.install() の symlink 先を Contents/MacOS/befold-cli に変更する。CLIShimInspector の鮮度チェックを拡張し、symlink 先のファイル名が befold-cli であることも検証する。旧 shim (Contents/MacOS/befold を指す symlink) は staleSymlink と判定し、既存の通知バナーで再インストールを案内する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 CLIInstaller.install() が Contents/MacOS/befold-cli への symlink を作成する
- [ ] #2 CLIShimInspector が symlink 先のファイル名が befold-cli でない場合を staleSymlink と判定する
- [ ] #3 旧 shim (Contents/MacOS/befold を指す) がアップデート後に staleSymlink として検出される
- [ ] #4 再インストール通知バナーが正常に表示される
- [ ] #5 既存の CLIShimInspector/CLIInstaller テストが更新されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLIInstaller.targetExecutablePath を befold-cli に変更。CLIShimInspector は既存ロジックで旧 shim を staleSymlink と自動判定。テスト期待値更新済み。
<!-- SECTION:NOTES:END -->
