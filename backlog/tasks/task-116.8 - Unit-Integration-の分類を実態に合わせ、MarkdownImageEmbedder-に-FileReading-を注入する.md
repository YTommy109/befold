---
id: TASK-116.8
title: Unit/Integration の分類を実態に合わせ、MarkdownImageEmbedder に FileReading を注入する
status: To Do
assignee: []
created_date: '2026-07-23 23:20'
labels:
  - test
  - cleanup
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 30800
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
coding_rule.md:571-583 は「実ファイルシステムへの読み書き」を Integration の代表例に挙げ、例外は `DirectoryLister` / `DefaultFileReader` のみと明記しているが、実態と乖離している。

## 1. 実 FS I/O があるのに ~IntegrationTests.swift 命名でないファイル

数字は `TempDir()` / `FileManager.default` の出現数。

| ファイル(BefoldApp/befoldTests/) | 件数 | 方針 |
|---|---|---|
| ViewerWindowControllerTests.swift | 42 | 一部は InMemoryFileReader へ置換可(`ViewerWindowController.init` は store 注入可) |
| ViewerWindowManagerTests.swift | 20 | 同上 |
| MarkdownImageEmbedderTests.swift | 13 | 下記 2 の解消が前提 |
| CLIInstallerTests.swift | 12 | 実書き込みが対象そのもの -> リネームが妥当 |
| CLIShimInspectorTests.swift | 8 | 同上 -> リネームが妥当 |
| ViewerWindowControllerToolbarTests.swift | 8 | 一部置換可 |
| ViewerWindowControllerCLIOptionsTests.swift | 7 | 一部置換可 |
| CLICheckCommandTests.swift | 5 | 前半は既に InMemoryFileReader 使用で良好。後半 4 件(:84,:99,:116,:129)のみ実 FS |
| ViewerLoadPipelineTests.swift | 5 | 画像埋め込みキャッシュ検証(:94,:122)が実 PNG 依存 |
| SessionRestorerTests / ViewerWebViewCoordinatorTests / ViewerWindowControllerSourceModeTests / ViewerWindowManagerDisplayOverridesTests | 各 3 | 一部置換可 |
| BookmarkStoreTests / ContentLoaderTests / ViewerStoreTests | 各 1 | symlink 検証のみ実 FS 必須 |

全部を機械的にリネームするのではなく、「モックに置換できるもの」と「実 FS が検証対象そのもので Integration が正しいもの」を切り分けること。

## 2. MarkdownImageEmbedder に依存注入が無い(プロダクト側の問題)

`BefoldApp/BefoldKit/MarkdownImageEmbedder.swift:28-33` の `embedLocalImages(in:baseURL:maxImageSizeBytes:)` は `FileReading` を受け取らず内部で直接 FS を読む。coding_rule.md:325-328 の「外部依存はプロトコル + デフォルト引数付きイニシャライザ注入」違反で、その結果テストが実 FS に縛られている。

さらに同 :21 の `private static let cache = DataURICache()` は**プロセス全体で共有される静的可変状態**で、`ViewerLoadPipelineTests.swift:94`(キャッシュが温まることを検証)と :122(温まらないことを検証)がテスト実行順に依存する危険がある。

## 3. スイートの同居によるファイル肥大

- `ViewerStoreFileGoneTests.swift` — :87 に `ViewerStoreLoadRaceTests`、:203 に `ViewerStoreFileGoneTests` の 2 スイートが同居
- `ViewerStoreTests.swift`(32.5KB / 917 行) — :86 `ViewerStoreTests`、:537 `ViewerStoreLoadingTests`、:573 `ViewerStoreChunkTests` の 3 スイート + :6 `MockFileWatcher` が同居。SwiftLint の file_length(400 行)超過が疑われ、coding_rule.md:210「1 ファイル 1 主要型」にも反する
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ~IntegrationTests.swift 命名が、実 FS/実 WKWebView に触れるテストと一致している
- [ ] #2 モックに置換可能だった実 FS 依存が InMemoryFileReader 等に置き換わっている
- [ ] #3 MarkdownImageEmbedder がファイル読み込み依存を注入で受け取れる
- [ ] #4 DataURICache の静的共有状態がテストの実行順に影響しない
- [ ] #5 1 ファイルに複数スイートが同居している箇所が分割されている
<!-- AC:END -->
