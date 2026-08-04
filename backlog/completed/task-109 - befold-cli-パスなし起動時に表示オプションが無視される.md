---
id: TASK-109
title: 'befold-cli: パスなし起動時に表示オプションが無視される'
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 12:18'
updated_date: '2026-07-23 16:54'
labels:
  - bug
  - cli
dependencies: []
priority: high
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLIAppLauncher で paths が空の場合、guard !paths.isEmpty else { return 0 } で即座に終了するため、--hidden-files 等の表示オプションが befold.app に転送されない。オプションのみ指定時のフォワーディング動作のテストも欠落している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 表示オプションのみ（パスなし）で befold-cli を実行した場合、オプションが befold.app に転送される
- [x] #2 paths=[] かつ options != default のケースをカバーするテストが存在する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIAppLauncher.run() の line85 'guard !paths.isEmpty else { return 0 }' を 'paths.isEmpty && options == CLIOpenOptions()' の場合のみ早期returnするよう修正(既存インスタンスありケースの条件と揃える)\n2. CLIAppLauncherTests に paths=[] かつ options!=default で forward が呼ばれることを検証するテストを追加\n3. swift test で既存テストが壊れていないことを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CLIAppLauncher.run() の 85行目 guard を 'paths.isEmpty && options==default' の場合のみ早期returnするよう修正(既存インスタンスありケースの分岐条件と統一)。CLIAppLauncherTests に paths=[] かつ options!=default で forward が呼ばれることを検証するテスト(launchWithNoPathsButNonDefaultOptionsForwards)を追加。post-edit hook(swift build/swift test --skip Integration --skip FileWatcherTests)が全編集後にエラーなく完了しており、既存テスト・新規テストとも通過を確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLIAppLauncher.run() で paths=[] かつ options!=default の場合、アプリ新規起動後のフォワーディングがスキップされ表示オプションが失われるバグを修正。85行目の早期returnガードを 'paths.isEmpty && options==CLIOpenOptions()' 条件に変更し、既存インスタンスありケース(67行目)と条件を統一した。CLIAppLauncherTests に launchWithNoPathsButNonDefaultOptionsForwards を追加し、paths=[]・options!=default で forward が呼ばれることを検証。post-edit hook の swift build/swift test --skip Integration --skip FileWatcherTests がエラーなく完了し、既存・新規テストの通過を確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
