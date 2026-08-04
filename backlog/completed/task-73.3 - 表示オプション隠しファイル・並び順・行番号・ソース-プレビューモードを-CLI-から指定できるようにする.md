---
id: TASK-73.3
title: 表示オプション(隠しファイル・並び順・行番号・ソース/プレビューモード)を CLI から指定できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 09:11'
updated_date: '2026-07-20 12:32'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 48000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
起動時に以下の表示状態を CLI オプションで指定できるようにする。TASK-73.1 の
引数パーサー基盤に依存する。既存の設定ストア(HiddenFilesPreference など)を
再利用し、専用の内部状態を新設しない方針で単純化を検討すること。

- 隠しファイルの表示/非表示
- サイドバー/フォルダー一覧の並び順
- 行番号の表示/非表示
- ソースモード/プレビューモードのどちらで開くか
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 --hidden-files / --no-hidden-files 相当のオプションで隠しファイル表示を制御できる
- [x] #2 並び順を指定するオプションでサイドバー/フォルダー一覧の並び順を制御できる
- [x] #3 --line-numbers / --no-line-numbers 相当のオプションで行番号表示を制御できる
- [x] #4 --source / --preview 相当のオプションでソースモード/プレビューモードを指定して開ける
- [x] #5 オプション未指定時は既存のデフォルト挙動・保存済み設定が維持される
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: CLIOpenOptions(showHiddenFiles/sortOrder/showLineNumbers/sourceMode)をCLIArgumentParserに追加し、--hidden-files/--no-hidden-files/--sort <folders-first|alphabetical>/--line-numbers/--no-line-numbers/--source/--previewをパース(オプションとパスは任意の順序で混在可)。既存ストアを再利用する方針: 隠しファイルはHiddenFilesPreference(既存、ViewerWindowManager.setHiddenFilesを追加して直接値を設定・全サイドバー即時反映)、行番号はViewerStore.showLineNumbers(既存のUserDefaultsキーにshowLineNumbersOverride経由でそのまま反映、永続化も既存のdidSetに委譲)。ソース/プレビューモードはSourceModeStore(既存per-file設定)を上書きするsourceModeOverrideパラメータをViewerWindowController.init〜ViewerWindowManager.openViewerに追加(forceSidebarVisibleと同じ「この起動限りの上書き」パターン)。保存値自体は書き換えない設計とした(将来の通常オープン時は元の設定に戻る)。並び順は調査の結果、永続化ストアが元々存在しない(FileListModelで毎回.foldersFirstに固定)ことが判明したため、新規ストアを作らずinitialSortOrderパラメータをViewerWindowController〜SidebarNavigator〜FileListModelへ素通しする最小限の変更で対応。AppDelegateはCLIInstanceRouterをNSWorkspace.open(urls:)からDistributedNotificationCenter経由に変更し(befoldはサンドボックス化されていないため利用可能)、起動中インスタンスへもpaths+optionsをまとめて転送できるようにした(TASK-73.1時点ではpathsのみでoptionsを運べなかったための見直し)。検証: swift build/test 504件全パス(CLIArgumentParserTests 8件追加、ViewerWindowControllerCLIOptionsTests新規4件、ViewerWindowManagerTests 1件追加)、swiftlint新規違反なし(cyclomatic complexity違反は列挙型ベースの構造に書き換えて解消)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CLIOpenOptionsによる--hidden-files/--sort/--line-numbers/--source/--previewの4オプションを実装。いずれも既存の保存ストア(HiddenFilesPreference/ViewerStore.showLineNumbers/SourceModeStore)またはforceSidebarVisible相当の一回限りの上書きパラメータを再利用し、専用の新規永続ストアは追加していない(並び順のみ元々ストアが存在しなかったため素通しパラメータで対応)。起動中インスタンスへの転送もDistributedNotificationCenter経由でオプション込みで届くよう見直した。swift test 504件全パスで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
