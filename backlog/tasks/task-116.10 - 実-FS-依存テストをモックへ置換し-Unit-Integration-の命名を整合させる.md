---
id: TASK-116.10
title: 実 FS 依存テストをモックへ置換し Unit/Integration の命名を整合させる
status: To Do
assignee: []
created_date: '2026-07-24 00:59'
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
- [ ] #1 モックに置換可能な実 FS 依存が InMemoryFileReader 等に置き換わっている
- [ ] #2 実 FS が検証対象そのものであるテストは ~IntegrationTests.swift 命名になっている
- [ ] #3 どのテストをモック化し、どれを Integration として残したかの判断理由が記録されている
<!-- AC:END -->
