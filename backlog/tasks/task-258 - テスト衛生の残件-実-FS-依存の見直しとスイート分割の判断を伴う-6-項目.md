---
id: TASK-258
title: 'テスト衛生の残件: 実 FS 依存の見直しとスイート分割の判断を伴う 6 項目'
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-08-02 00:01'
updated_date: '2026-08-02 03:36'
labels: []
dependencies:
  - TASK-251
priority: low
type: task
ordinal: 452700
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-251 から切り出した、設計判断を伴う項目。TASK-251 は共有ヘルパーへの機械的な置換に絞って完了させたため、判断が必要な以下を別途扱う。
1. RecentRepositoriesStoreTests の pruneMissingAsync を InMemoryFileReader(directories:) 化する。実 FS でしか検証できない性質が含まれていないかの判断が要る。pruneMissingAsync 内部の Task.detached(priority: .utility) は CI 高負荷時に utility QoS のスケジューリング遅延を受けやすく、実 FS 分と合わせて変動要因になっている
2. CLICheckAndBookmarkDefaultsTests の Integration 命名の是正と、PerFileStateStoreSymlinkIntegrationTests との symlink 検証の重複整理。**別スイートへ分けると並列実行される**ため、計測の前提や共有状態がないかの判断が要る(TASK-244 でこの落とし穴を踏んで Critical になった実例あり)
3. DirectoryListerTests の実 $HOME 全走査(listEntriesNoParentAtHome)を home 注入 + TempDir 化する。DirectoryLister.isWithinHome がホームをハードコードしているため、プロダクトコードへの注入シーム追加を伴う。実ホームの中身に依存して遅く、環境依存のフレーク要因でもある
4. ViewerWindowManagerTests の makeTabGroup(static 純関数)を非 @MainActor スイートへ切り出す。スイート分割の並列実行影響の判断が要る
5. CLIAppLauncherTests の終了コード/stderr ペアテストの統合と runLauncher ファクトリ抽出
6. MainMenuBuilderTests と MenuShortcutCatalogTests の buildMenu() 重複解消。両ファイルで引数の有無など書き味が異なり、共通化の形に設計判断が要る
注意: 今回の一連のレビューで「移設・統合・共通化の過程で元のテストが固定していた不変条件が静かに失われる」事故が 4 件見つかっている(いずれも落ちるのではなく通ってしまう方向の劣化)。着手前に元テストの assertion を列挙し、変更後に照合すること。可能なら検証対象のロジックを一時的に壊して落ちるかを確認する。
価値は実行時間ではなくテスト分類の正確さと重複の解消(対象スイートは全体時間にほぼ寄与しない)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 各項目が是正されるか、見送る場合は実際に代替を試した上での理由が記録される
- [x] #2 別スイートへ分割する項目について、並列実行による影響がないことが確認されている
- [x] #3 移設前後で検証している不変条件が同じ強度で保たれている
- [x] #4 フル swift test を 3 回連続で実行しグリーン
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 各項目ごとに元テストの assertion を列挙してから着手し、変更後に照合する
2. RecentRepositoriesStore の pruneMissingAsync を InMemoryFileReader(directories:) 化
3. CLICheckAndBookmarkDefaults の Integration 命名是正と symlink 重複整理(スイート分割はしない方向で検討)
4. DirectoryLister に home 注入シームを追加し listEntriesNoParentAtHome を TempDir 化
5. ViewerWindowManager makeTabGroup テストの整理
6. CLIAppLauncherTests の runLauncher ファクトリ抽出と終了コード/stderr ペア統合
7. MainMenuBuilderTests / MenuShortcutCatalogTests の buildMenu 重複を共有フィクスチャへ
8. フル swift test を 3 回連続グリーン
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実施(2026-08-02): 6 項目すべて対応。各項目とも着手前に元テストの assertion を列挙し、変更後に照合した。
1. RecentRepositoriesStore: pruneMissingAsync が触る FS は fileReader.isDirectory のみと確認し、3 テストとも InMemoryFileReader(directories:) 化。makeStore(defaults:existingDirectories:) を追加し、store 側と同じ normalizedPathKey でキーを作ることで両者のドリフトを防いだ
2. CLICheckAndBookmarkDefaultsTests: docs/dev/rules/testing.md の基準では実 FS を使うため Integration が正しく、命名は「不足」方向のずれだった。CLICheckAndBookmarkDefaultsIntegrationTests へ改名。symlink テストは CLIBookmarkCommand が一切パス解決をしていないことを確認し、BookmarkStore の正規化の再検証(PerFileStateStoreSymlinkIntegrationTests と重複)を削除、代わりに『CLI は symlink パスを未解決のまま forward する』を明示的に検証する形へ。スイート分割はしていない
3. DirectoryLister: FileReading への homeDirectory 追加(公開プロトコルの責務外・波及大)を退け、既存の fileReader と同じ『デフォルト引数で注入』イディオムに揃えて home: URL = defaultHome を追加。listEntriesAsync は SidebarNavigator が関数参照として渡しており既定引数が効かないためシグネチャ据え置き。実 $HOME の全走査と $HOME への書き込みが 5 テストから消えた
4. ViewerWindowManager makeTabGroup: 非 @MainActor スイートへの分離は見送り(同スイートに既に純関数テストが同居、スイート内は元々並列、分離しても並列度は増えず TASK-244 型のリスクだけ増える)。単独ウィンドウ/順序保持の 2 件を @Test(arguments:) 化し、先頭タブ選択のケースを追加(first と selected の取り違えを検出できるようになった)
5. CLIAppLauncherTests: runLauncher(...) と『2 回目の poll で見つかる』findRunningInstance ファクトリを抽出。終了コードと stderr の 2 ペアを統合。launchAndForward 系は forward スタブが異なるため統合していない
6. MainMenuFixture.swift を新設し、2 スイートの StubMenuDelegate/buildMenu/localizedTitle の重複を解消。MainMenuBuilder.build は NSApp.helpMenu への副作用があるためメモ化を維持し、注入対象の delegate を build 引数ではなく init 引数にすることでメモ化と注入を両立させた
検証: swift test フル 3 回連続グリーン(948 tests / 142 suites)。1 回目に CLIRequestWireIntegrationTests が Distributed Notification 待ちで落ちたが、本件の変更対象外で単独実行 3 回・フル 3 回とも再現せず、TASK-257 で扱う既知の脆弱性と判断した
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-251 から切り出したテスト衛生の残件 6 項目を対応した。実 FS 依存の排除(pruneMissing の InMemoryFileReader 化、DirectoryLister への home 注入シーム追加による実 $HOME 全走査の除去)、Integration 命名の是正と symlink 検証の重複解消、テストヘルパー抽出とパラメタライズ、メニュー 2 スイートの共有フィクスチャ化を行った。スイート分割は 2 件とも並列度の利得がなく TASK-244 型のリスクのみ増えるため見送り、理由を記録した。各項目で変更前後の assertion を照合し不変条件の強度を維持している。swift test フル 3 回連続グリーンで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
