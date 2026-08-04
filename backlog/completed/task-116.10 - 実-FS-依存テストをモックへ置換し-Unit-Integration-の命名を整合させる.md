---
id: TASK-116.10
title: 実 FS 依存テストをモックへ置換し Unit/Integration の命名を整合させる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-24 00:59'
updated_date: '2026-07-24 12:10'
labels:
  - test
  - cleanup
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 31000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-116.8 から分離（ユーザー判断により別タスク化）。対象規模が大きく、1 PR に収めるには過大なため。

`docs/dev/coding_rule.md` は「実ファイルシステムへの読み書き」を Integration の代表例に挙げ、例外は `DirectoryLister` / `DefaultFileReader` のみと明記しているが、実態が乖離している。

## 対象（`TempDir(` / `FileManager.default` の出現数、2026-07-24 時点）

| ファイル（BefoldApp/befoldTests/） | 件数 |
|---|---|
| ViewerWindowControllerTests.swift | 42 |
| DirectoryListerTests.swift | 37 |
| ViewerWindowManagerTests.swift | 20 |
| MarkdownImageEmbedderTests.swift | 13 |
| ViewerWindowControllerToolbarTests.swift | 8 |
| DefaultFileReaderTests.swift | 8 |
| ViewerWindowControllerCLIOptionsTests.swift | 7 |
| ViewerLoadPipelineTests.swift | 5 |
| CLICheckCommandTests.swift | 5 |
| SessionRestorerTests / ViewerWebViewCoordinatorTests / ViewerWindowControllerSourceModeTests / ViewerWindowManagerDisplayOverridesTests | 各 3 |
| BookmarkStoreTests / ContentLoaderTests / ViewerStoreTests / ZoomStoreTests / SidebarStateStoreTests / ScrollPositionStoreTests | 各 1 |

## 進め方の注意

全部を機械的にリネームするのではなく、「モックに置換できるもの」と「実 FS が検証対象そのもので Integration が正しいもの」を切り分けること。判断を先にやらないと、モックへ置換すべきテストにまで Integration の名前が付いて固定化する。

- `ViewerWindowController.init` は `store:` を注入でき、`store` 経由で `InMemoryFileReader` を渡せる。ただし `directoryLister` クロージャは注入可でも `fileURL` の実在を前提にする経路が残るため、一部は実 FS のままになる可能性がある。
- `CLICheckCommandTests` は前半が既に `InMemoryFileReader` を使っており良好。後半 4 件のみ実 FS（ディレクトリ列挙・dangling symlink が対象なので Integration 相当）。
- `DefaultFileReaderTests` / `DirectoryListerTests` は coding_rule.md が明示する例外。
- `MarkdownImageEmbedderTests` の置換は TASK-118 の依存注入が前提。

## 済んでいる分

TASK-116.8 で、実 FS 書き込みが検証対象そのものである 2 ファイルはリネーム済み（`CLIInstallerTests` → `CLIInstallerIntegrationTests`、`CLIShimInspectorTests` → `CLIShimInspectorIntegrationTests`）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 モックに置換可能な実 FS 依存が InMemoryFileReader 等に置き換わっている
- [x] #2 実 FS が検証対象そのものであるテストは ~IntegrationTests.swift 命名になっている
- [x] #3 どのテストをモック化し、どれを Integration として残したかの判断理由が記録されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
スコープ確定(ユーザー判断 2026-07-24): 製品変更なしでモック化できる分を置換し、DI 配線の穴でモック不可な分は ~IntegrationTests へリネーム。製品側の配線修正(ViewerLoadPipeline embedder / DirectoryLister 静的チェック注入化)は別タスクへ分離。

1. (A) ContentLoaderTests — 残 1 件(PNG)を InMemoryFileReader.setBinary/setDataFile へ置換
2. (C) CLICheckCommandTests — 後半4件(ディレクトリ列挙/dangling symlink)を CLICheckCommandIntegrationTests.swift へ分離。前半5件は unit のまま
3. (C) symlink 解決テスト4本 — Bookmark/Zoom/Sidebar/ScrollPosition の各1件を Integration スイートへ抽出。残りは unit
4. (C) ViewerWindowControllerCLIOptionsTests — store 注入に fileReader:InMemoryFileReader を追加し純オプション系を unit 化(switch を含むものは 5 へ)
5. 配線の穴でモック不可な分 → ~IntegrationTests へリネーム: VWC本体の switch/rename 系, Toolbar, SourceMode, Manager, DisplayOverrides, SessionRestorer, 画像埋め込み系(ViewerLoadPipeline embed ウォームアップ/ViewerWebViewCoordinator)。これらは『Integration by 配線制約』であり本質的 Integration ではない旨を AC#3 に明記
6. 配線修正のフォローアップタスクを作成し、5 のテストは配線修正後に再モック化する旨をリンク
7. swift test で全 green を確認、AC#3 に判断理由を記録

備考: DefaultFileReaderTests/DirectoryListerTests は coding_rule.md:594-595 の明示例外につきリネームしない。MarkdownImageEmbedderTests/ViewerStoreTests は移行済み。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 分類調査結果 (2026-07-24)

coding_rule.md:592-595 の判定基準「テスト対象自体をインメモリ/モックに差し替えられず OS・FS・別プロセスの実挙動が結果を左右するなら Integration。差し替え可能な純粋ロジックは unit」に照らして分類。

### 既に移行済み(対応不要)
- MarkdownImageEmbedderTests(InMemoryFileReader へ移行済み) / ViewerStoreTests(全面 InMemory)。タスク起票時の件数(13/1)は移行前スナップショット。

### (B) 実 FS が SUT の規約明示例外 → リネームしない
- DefaultFileReaderTests / DirectoryListerTests(coding_rule.md:594-595 が名指し)

### (A) 製品変更なしでモック置換可能
- ContentLoaderTests: 残 1 件(PNG 読込)を InMemoryFileReader.setDataFile/setBinary へ

### (C) 製品変更なしで一部モック化 + 一部 Integration 分離
- CLICheckCommandTests: 前半5件は既に InMemory(unit)。後半4件(ディレクトリ列挙/dangling symlink)を IntegrationTests へ分離
- BookmarkStore/Zoom/Sidebar/ScrollPosition の各1件(symlink 解決検証)を Integration へ抽出。残りは UserDefaults 純ロジックで unit
- ViewerWindowControllerCLIOptionsTests: store 注入に fileReader:InMemoryFileReader を追加し純オプション系を unit 化。switch を含むものは製品変更待ち

### (C) 製品側の配線修正が前提 → 単独ではモック化不可
DI 経路の穴が2つ:
1. ViewerLoadPipeline.swift:116 が MarkdownImageEmbedder.shared(=DefaultFileReader 固定)を呼び、注入 fileReader を無視 → ViewerLoadPipeline/ViewerWebViewCoordinator の画像埋め込み系テストはモック化不可
2. ViewerWindowController.swift:291(switchFile の DirectoryLister.isExistingFile) / :373(handleRename の fileExists) / ViewerWindowManager.swift:85(openViewer の fileExists) が注入 fileReader を通らない静的 FS 呼び出し → VWC本体/Toolbar/SourceMode/Manager/DisplayOverrides/SessionRestorer の switch/rename/open 系テストはモック化不可

対象: ViewerWindowControllerTests(42) の switch/rename 系, ViewerWindowControllerToolbarTests, ViewerWindowControllerSourceModeTests, ViewerWindowManagerTests(20), ViewerWindowManagerDisplayOverridesTests, SessionRestorerTests

配線修正は TASK-116.12 へ分離。本タスクで ~IntegrationTests へリネームする switch/rename/open/画像埋め込み系は『Integration by 配線制約』であり、116.12 の配線修正後に unit へ戻す想定。

## 実装進捗 (slice 1-4 完了, 2026-07-24)
- slice1: ContentLoaderTests の PNG テストを InMemoryFileReader.setDataFile へ置換、実 FS loader プロパティ削除
- slice2: CLICheckCommandTests 後半4件(ディレクトリ列挙/dangling symlink)を CLICheckCommandIntegrationTests.swift へ分離
- slice3: Bookmark/Zoom/Sidebar/ScrollPosition の symlink 解決テスト4本を PerFileStateStoreSymlinkIntegrationTests.swift へ集約
- slice4: ViewerWindowControllerCLIOptionsTests 全7件を store 注入(MockFileWatcher + InMemoryFileReader)+ 合成パス + 空 directoryLister でモック化。実 FS/実 watcher とも不使用に
検証: 上記4スイート16 tests green。フック(swift test --skip Integration)も各編集で green。

## slice5 分類確定 (2026-07-24)
製品コード確認: (a) ViewerWindowController.swift:101 の注入 directoryLister は init 同期一覧のみに使われ SidebarNavigator へ渡らない→ navigate/refresh/switch は静的 DirectoryLister(:291/:373) を踏む (b) openViewer は WM:85 (c) 画像埋め込みは renderableContent:177 / pipeline:116 の shared。

ファイル別(モック可 / Integration):
- ViewerWindowControllerTests: 11 / 19
- ToolbarTests: 5 / 3
- SourceModeTests: 1 / 2
- ManagerTests: 1(純関数 isDetachedFromSpace) / 20
- DisplayOverridesTests: 0 / 6(丸ごと)
- SessionRestorerTests: 0 / 3(丸ごと, restore→openViewer→WM:85)
- LoadPipelineTests: 3 / 2
- WebViewCoordinatorTests: 6 / 1

方針: Integration 分は ~IntegrationTests.swift へ移動、モック可分は CLIOptions と同じ MockFileWatcher+InMemoryFileReader パターンで unit 化。丸ごと=DisplayOverrides/SessionRestorer。Manager は純関数1件を unit 残し20件を Integration へ。

## slice5 実装完了 + 検証 (2026-07-24)

### 作成した Integration ファイル(8)
ViewerWindowManagerDisplayOverridesIntegrationTests(git mv), SessionRestorerIntegrationTests(git mv), ViewerWindowManagerIntegrationTests, ViewerWindowControllerIntegrationTests, ViewerWindowControllerToolbarIntegrationTests, ViewerWindowControllerSourceModeIntegrationTests, ViewerLoadPipelineIntegrationTests, ViewerWebViewCoordinatorIntegrationTests。各 @Suite に Integration 理由を1行記載。

### 最終仕分け(モック化 unit / Integration 移動)
- ViewerWindowController 9 / 21, Toolbar 5 / 3, SourceMode 1 / 2, Manager 1(純関数) / 20, DisplayOverrides 0 / 6, SessionRestorer 0 / 3, LoadPipeline 3 / 2, WebViewCoordinator 3 / 3

### 当初分類から変更(検証を弱めないルール適用)
- sidebarIncludes/ExcludesHiddenFilesWhenPreference: 実 DirectoryLister の隠しファイルフィルタそのものを検証しているためモック化せず Integration へ(VWC の移動が19→21)
- WebViewCoordinator の source/embedImages=false の非埋め込み2件: 実 image.png が存在してもなお埋め込まないことの検証で実 FS が意味を持つため、renderedMode と同じく Integration へ集約(メインで実施、WebViewCoordinator 移動 1→3)

### AC#3 判断理由
実 FS 依存は3層に分類した:
(a) 実 FS が SUT そのもの(DefaultFileReader/DirectoryLister、symlink 解決、ディレクトリ列挙、dangling symlink、隠しファイルフィルタ、画像埋め込みの実読込) → coding_rule.md:594-595 の例外は unit 名のまま、それ以外は ~IntegrationTests 命名
(b) モック化可能(init/表示状態のみ) → InMemoryFileReader + MockFileWatcher へ置換
(c) 配線の穴(ViewerLoadPipeline:116 の shared / VWC:291,373 / WM:85)で製品変更なしにはモック不可 → 『Integration by 配線制約』として ~IntegrationTests へ移動し、TASK-116.12 の配線修正後に unit へ戻す想定(相互リンク済み)

### 検証
- swift build/test(ビルド時 SwiftLint プラグイン込み) exit 0、全 607 tests / 87 suites green
- ファストレーン(swift test --skip Integration) 511 tests / 3.3秒(従来比で switch/open/実FS系 96件が Integration レーンへ分離、真の unit のみに)
- swiftformat --lint 0 files require formatting
- file_length: 最大 507 行(既存の ViewerWindowController 623/ViewerStoreTests 524 と同水準、error 閾値1000以下)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
実 FS 依存テストを3層(実FSがSUT / モック可 / 配線制約でモック不可)に切り分け、モック可分を InMemoryFileReader+MockFileWatcher へ置換、実FS依存分を ~IntegrationTests へ命名分離した。製品側の配線修正が必要な分は TASK-116.12 へ分離。検証: 全607 tests green、ファストレーン(--skip Integration)が511 tests/3.3秒に短縮され真の unit のみに、swiftformat/SwiftLint(ビルド時)とも通過。
<!-- SECTION:FINAL_SUMMARY:END -->
