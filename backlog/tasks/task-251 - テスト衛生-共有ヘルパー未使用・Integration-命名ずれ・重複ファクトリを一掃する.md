---
id: TASK-251
title: 'テスト衛生: 共有ヘルパー未使用・Integration 命名ずれ・重複ファクトリを一掃する'
status: To Do
assignee: []
created_date: '2026-08-01 10:47'
labels: []
dependencies: []
priority: low
type: task
ordinal: 453000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CI レビューで見つかった小粒の規約違反・構造課題のまとめ(TASK-67 / TASK-1.6 と同系のまとめタスク)。
共有ヘルパー未使用(規約の明示違反):
- HostedPanelWindowControllerTests.swift:13-16: UserDefaults(suiteName:) + removePersistentDomain の手書き。makeIsolatedDefaults へ(現状は ~/Library/Preferences に plist が残る)
- CLIInstallerTranslocationTests.swift:39-42: 手組み一時ディレクトリ。TempDir へ
- TrackedPathResolverTests.swift:34-67: FakeFileReader 自作。InMemoryFileReader で代替し削除
重複ファクトリ・繰り返しセットアップ:
- WindowFrameStoreTests.swift: 全 12 テストで defaults 生成+store 組み立てをインライン展開(兄弟スイート BookmarkStoreTests の流儀へ)
- MainMenuBuilderTests.swift:17-34 / MenuShortcutCatalogTests.swift:18-34: buildMenu 定型の重複。さらに MenuShortcutCatalogTests は entries→groups→buildMenu 連鎖でフルメニュー構築を 10 回超実行しており、1 回構築して使い回す(@MainActor 直列区間の短縮)
- ViewerRendererMessageHandlingTests.swift: 3 行セットアップ 17 回反復を makeSUT へ。:388-390 ephemeralDefaults は makeIsolatedDefaults の別名で不要
- CLIAppLauncherTests.swift:65-144, 222-246: 終了コード/stderr のペアテストを統合し runLauncher ファクトリを抽出(run 実行 3 回削減)
命名・分類:
- CLICheckAndBookmarkDefaultsTests.swift: 実 FS 使用なのに非 Integration 命名。symlink 検証は PerFileStateStoreSymlinkIntegrationTests と重複しており store 層へ一本化を検討
- RecentRepositoriesStoreTests.swift:246-283: pruneMissingAsync 2 本を InMemoryFileReader(directories:) 化(実 FS 不要)
- PerFileStateStoreSymlinkIntegrationTests.swift:16,19: prefix が BookmarkStoreTests のコピペ
その他:
- ViewerWindowManager 系 / SessionRestorerTests: fixture.closeAll() を defer 化(#require 失敗時に実ウィンドウがリークし後続テストの MainActor 負荷になる。closeAll 自体が無いテストもある: RecentRepositoriesTests.swift:119-132)
- ViewerWindowManagerTests.swift:272-318: makeTabGroup は static 純関数。非 @MainActor スイートへ切り出し並列レーンで実行
- InfoPlistTests.swift:12-30 / QuickLookInfoPlistTests.swift:66-74: plist をテストごとに再パース。static let キャッシュ化し、読めない場合は #require で即失敗
- DirectoryListerTests.swift:287-293: 実 $HOME 全列挙(サブフォルダー内部まで走査)で遅く環境依存。home を注入可能にし(DirectoryLister.swift:87-88)、TempDir を home として渡す(実ホームへの一時ディレクトリ作成も不要になる)
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 各項目が是正される(見送る場合は代替を試した上で理由を記録する)
- [ ] #2 makeIsolatedDefaults / TempDir / InMemoryFileReader の共有ヘルパーへ統一される
- [ ] #3 closeAll が defer 化され失敗時のウィンドウリークがなくなる
- [ ] #4 swift test が全てグリーン
<!-- AC:END -->
