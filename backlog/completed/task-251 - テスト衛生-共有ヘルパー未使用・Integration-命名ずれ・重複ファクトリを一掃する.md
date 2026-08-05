---
id: TASK-251
title: 'テスト衛生: 共有ヘルパー未使用・Integration 命名ずれ・重複ファクトリを一掃する'
status: Done
assignee:
  - '@claude'
created_date: '2026-08-01 10:47'
updated_date: '2026-08-02 00:51'
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
- [x] #1 各項目が是正される(見送る場合は代替を試した上で理由を記録する)
- [x] #2 makeIsolatedDefaults / TempDir / InMemoryFileReader の共有ヘルパーへ統一される
- [x] #3 closeAll が defer 化され失敗時のウィンドウリークがなくなる
- [x] #4 swift test が全てグリーン
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
スコープをチームリードと合意し、機械的・低リスクな7項目に絞って実装・コミット済み(9be4e13, test/improve_test)。残りはチームリードが別タスクへ切り出す予定。詳細はコミットメッセージと report.md 参照。

レビュー修正ラウンド1完了・コミット済み(2dd3a4d)。delegate weak 早期解放/TempDir 早期削除の2件+任意1件。フル swift test 3回連続 genuine green。詳細は report.md 参照。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
共有ヘルパーへの統一と衛生の一掃を 9 項目実施した(HostedPanel の makeIsolatedDefaults 化 / CLIInstallerTranslocation の TempDir 化 / TrackedPathResolver の InMemoryFileReader 化 / PerFileStateStoreSymlink の prefix 修正 / ViewerRendererMessageHandling の makeSUT 抽出 / InfoPlist・QuickLookInfoPlist の static let キャッシュ化 / closeAll の defer 化 / WindowFrameStore のファクトリ集約 / MenuShortcutCatalog の buildMenu キャッシュ)。
当初 15 項目の予定だったが、設計判断を伴う 6 項目(実 FS 依存の判断・スイート分割の並列影響・プロダクトへの注入シーム追加)は TASK-258 へ切り出した。
レビュー指摘により、makeSUT の戻り値を _ で受けたことで weak な delegate が即座に解放されていた問題(現時点では assertion が delegate の生死に依存しないため誤った合格にはなっていないが、delegate を見るコードが入った瞬間に空振りへ変わる)と、TempDir の早期解放でテスト前提が崩れうる問題を修正した。
副次的に、キャッシュを可変 static var で実装すると並列実行下でクラッシュすることと、swift test をパイプ越しに判定すると失敗が隠れることを発見し、TASK-252 で規約化した。
検証: swift build 警告なし、フル swift test 3 回連続グリーン(set -o pipefail + 明示的な終了コード記録)。レビュー承認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
