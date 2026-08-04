---
id: TASK-73.11
title: パス引数なしのCLIオプション指定が新規起動時に無視される
status: Done
assignee:
  - '@claude'
created_date: '2026-07-20 13:30'
updated_date: '2026-07-21 00:28'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/AppDelegate.swift:142'
parent_task_id: TASK-73
priority: medium
type: bug
ordinal: 58000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppDelegate.applicationDidFinishLaunching は initialPaths が空の場合 restoreLastSession() のみを呼び、initialOptions を一切参照しない。既存インスタンスがなく新規起動する場合、`befold --hidden-files` のようなパスなし・オプションのみのCLI起動はパース自体は成功するにもかかわらず、指定したオプションが何にも適用されない無言の無効化(no-op)になる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 パス引数なしでもCLIオプション(隠しファイル表示・並び順・行番号・ソース/プレビューモード等)がセッション復元後のウィンドウ、または今後開くウィンドウに適用されること
- [x] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
SessionRestorer.restoreLastSession(options:)にCLIOpenOptionsを渡せるようにし、showHiddenFilesは復元直後にwindowManager.setHiddenFilesで即時反映、sortOrder/showLineNumbers/sourceModeは復元される各ウィンドウのopenViewer呼び出しへ渡す。AppDelegate.applicationDidFinishLaunchingのinitialPaths.isEmpty分岐でinitialOptionsを渡すよう変更する。重複していたsortOrder変換ロジックはCLIOpenOptions.viewerSortOrderへ切り出して共通化する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
SessionRestorer.restoreLastSession(options: CLIOpenOptions = CLIOpenOptions())を追加。showHiddenFilesは復元開始直後にwindowManager.setHiddenFilesで即時適用、sortOrder/showLineNumbers/sourceModeはrestoreTabGroupと『レイアウトに無いファイル』ループ双方のopenViewer呼び出しへ引き渡し、復元される全ウィンドウに反映されるようにした(保存済み設定自体は書き換えないこの起動限りの上書き、既存のCLI直接オープン時のoverride挙動と同じ設計)。AppDelegate.applicationDidFinishLaunchingはinitialPaths.isEmpty時にsessionRestorer.restoreLastSession(options: initialOptions)を呼ぶよう変更。sortOrder→SortOrder変換の重複ロジックをCLIOpenOptions.viewerSortOrderへ切り出しAppDelegate.openViewerからも再利用。SessionRestorerTests.swiftを新規追加し、--hidden-files/--line-numbers適用とオプション未指定時の従来動作維持を検証。swift test 525件全パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
パス引数なしのCLI起動(befold --hidden-files等)でもSessionRestorer.restoreLastSession(options:)経由で表示オプションが復元ウィンドウへ適用されるようにした。showHiddenFilesは即時グローバル反映、sortOrder/showLineNumbers/sourceModeは復元される各ウィンドウへこの起動限りの上書きとして適用する。
<!-- SECTION:FINAL_SUMMARY:END -->
