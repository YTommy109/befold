---
id: TASK-228
title: 「最近使ったリポジトリ」メニュー表示時の pruneMissing とアイコン取得をメニュー外へ逃がす
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:15'
updated_date: '2026-07-31 13:18'
labels:
  - refactor
  - performance
dependencies: []
priority: medium
type: task
ordinal: 350000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RecentRepositoriesMenuController.menuNeedsUpdate (befold/App/RecentRepositoriesMenuController.swift:25-41) がメニューを開いた瞬間の MainActor 上で pruneMissing()（最大 10 件の isDirectory stat）と NSWorkspace.icon(forFile:) を件数ぶん実行する。アンマウント済み/応答しないネットワークマウント上の worktree が履歴に残っていると File メニューを開いた瞬間に固まる。prune は起動時/定期の Task.detached へ移し、表示は保存済みリストをそのまま出す（存在しないものは開いた時点で既存の FileNotFound 経路に委ねる）。RecentDocumentsMenuController.swift:33 の icon 取得も同種。TASK-204（worktree 階層化）と同じファイルを触るため実施順に注意。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 メニューを開いた瞬間に stat・アイコン取得による MainActor ブロックが発生しない
- [x] #2 存在しないエントリの整理が別タイミングで行われ、開こうとした場合は既存のエラー経路で通知される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. RecentRepositoriesStore.swift: pruneMissing() を pruneMissingAsync() async に変更し、isDirectory(stat)を Task.detached で MainActor 外実行。
2. RecentRepositoriesMenuController.swift: menuNeedsUpdate から pruneMissing 呼び出しを削除(pruneMissing クロージャ自体も削除)。NSWorkspace.icon(forFile:) のパス毎ディスク I/O を、パス非依存の汎用フォルダーアイコン(NSWorkspace.icon(for: .folder))に置き換え。
3. AppDelegate.swift: RecentRepositoriesMenuController の初期化引数から pruneMissing を削除。applicationDidFinishLaunching の末尾で Task { await recentRepositoriesStore.pruneMissingAsync() } を起動時1回だけ実行。
4. SessionRestorer.swift: openRootFallback で resolveFileToOpen が nil を返すケース(worktree/リポジトリのルート自体が削除済み)に、既存の FileNotFoundUI 経路(presentFileNotFound、テスト用に注入可能)で通知するよう修正(従来は無反応だった)。
5. テスト: RecentRepositoriesMenuControllerTests から callsPruneMissingOnEveryUpdate を削除、makeController から pruneMissing 引数を削除。RecentRepositoriesStoreTests の3件の pruneMissing テストを pruneMissingAsync の async 呼び出しに変更。SessionRestorerTests に presentFileNotFound 注入用スタブを追加し、openRepositoryFallbackNotifiesFileNotFoundWhenResolutionReturnsNil で通知が実際に呼ばれることを検証(実 NSAlert.runModal は起動しない)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
swift test 887件全通過(Integration/FileWatcherTests除く)。SwiftLint 実行、変更ファイルに新規エラーなし。ViewerWindowControllerToolbarTests の1件のflaky失敗はフルスイート実行時のみ発生し、単独実行では3回連続成功を確認(task-228とは無関係の既存の並列実行タイミング起因)。ユーザーと協議の上、SessionRestorer.openRootFallback がリポジトリのルート自体が削除されているケースで無反応だった不具合も本タスクで併せて修正し、FileNotFoundUI 経路(テスト注入可能な presentFileNotFound 経由)で通知するようにした。ただし空フォルダ(root は実在するが対応ファイルが1つも無い)ケースも resolveFileToOpen が nil を返すため区別せず同じ通知になる(意図的な単純化)。RecentDocumentsMenuController.swift の同種のアイコン取得コストは本タスクの対象(「最近使ったリポジトリ」メニュー)外のため未対応、将来の別タスク候補として残す。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
RecentRepositoriesStore.pruneMissing を pruneMissingAsync(Task.detached で isDirectory 判定)に変更し、AppDelegate.applicationDidFinishLaunching で起動時1回だけ実行するようにした。RecentRepositoriesMenuController.menuNeedsUpdate からは pruneMissing 呼び出しと NSWorkspace.icon(forFile:) のパス毎ディスク I/O を除去し、汎用フォルダーアイコンを使うことでメニュー表示自体は保存済みリストの描画のみ(FS I/O なし)にした。SessionRestorer.openRootFallback がリポジトリルート削除時に無反応だった不具合も FileNotFoundUI 通知に修正。swift test 887件全通過で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
