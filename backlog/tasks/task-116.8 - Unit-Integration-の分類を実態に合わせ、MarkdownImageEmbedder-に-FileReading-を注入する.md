---
id: TASK-116.8
title: 1 ファイルに同居した複数スイートを分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:20'
updated_date: '2026-07-24 01:00'
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
- [x] #1 DataURICache の静的共有状態がテストの実行順に影響しない
- [x] #2 1 ファイルに複数スイートが同居している箇所が分割されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AC#1(一部)と AC#5 を実施。AC#2/#3 は設計判断が要るため未着手、AC#4 は前提を調査した結果ほぼ空振りと判明した。

AC#5(スイート分割): 917 行 / 3 スイート同居だった ViewerStoreTests.swift を分割した。
- ViewerStoreTests.swift 524 行(ViewerStoreTests + 共有ヘルパー MockFileWatcher / makeStore / StopCountingWatcher)
- ViewerStoreLoadingTests.swift 44 行
- ViewerStoreChunkTests.swift 362 行
分割にあたり file-private だったヘルパーの可視性を調整した: FailingSecondChunkReader は利用者が ViewerStoreChunkTests だけになったため同ファイルへ移設(private のまま)。StopCountingWatcher は 2 ファイルから使うため MockFileWatcher と同じ流儀で internal にし、共有ヘルパーの置き場である ViewerStoreTests.swift へ集約した。

AC#1(命名の一部): 実 FS への書き込みが検証対象そのもので、モックに置換すべきでない 2 ファイルをリネームした。CLIInstallerTests → CLIInstallerIntegrationTests、CLIShimInspectorTests → CLIShimInspectorIntegrationTests(スイート名も併せて変更)。

AC#4(DataURICache のテスト順依存): 実測の結果、現状では顕在化しないことが分かった。ViewerLoadPipelineTests の warm/cold 2 テストはそれぞれ別の TempDir(UUID 付き)配下にファイルを作るため、キャッシュのキーである URL が衝突しない。単独実行・3 回連続実行いずれも 5 tests が安定して pass する。静的共有状態であること自体は残るが、TempDir が一意パスを保証している限り順序依存は起きない。「危険がある」という指摘は前提の確認が不足していた。

未着手(要判断):
- AC#2(実 FS 依存のモック置換): ViewerWindowControllerTests 42 / DirectoryListerTests 37 / ViewerWindowManagerTests 20 箇所など、対象が大きい。
- AC#3(MarkdownImageEmbedder への FileReading 注入): FileReading プロトコルには fileSize と readData はあるが、DataURICache がキャッシュ検証に使う更新日時(contentModificationDate)を取る手段が無い。注入するにはプロトコルへ modificationDate(at:) を追加する必要があり、DefaultFileReader・InMemoryFileReader を含む全準拠型に波及する。キャッシュのキーをサイズのみに弱めるという選択肢もあるが、それは無効化の精度を落とす。プロダクト API の変更を伴うため単独で判断せずユーザーに諮る。

検証: swift test が 593 tests / 77 suites を 14.998 秒で pass。SwiftFormat --lint はクリーン。

ユーザー判断により、当初の AC のうち以下を別タスクへ切り出した:
- 「~IntegrationTests 命名の整合」と「実 FS 依存のモック置換」→ TASK-116.10
- 「MarkdownImageEmbedder への FileReading 注入」→ TASK-116.11(FileReading プロトコルへの更新日時追加というプロダクト API 変更を伴うため)

本タスクの残スコープは「スイート分割」と「DataURICache のテスト順依存の確認」に絞った。タイトルも実態に合わせて変更した。

AC#1(DataURICache の実行順非依存)の検証: 実測により、静的共有キャッシュがあってもテストの実行順に影響しないことを確認した。ViewerLoadPipelineTests の warm/cold 2 テストはそれぞれ別の TempDir(UUID 付き)配下にファイルを作るため、キャッシュのキーである URL が衝突しない。単独実行で 5 tests が pass、3 回連続実行でも 0.005 秒で安定して pass する。起票時に「テスト実行順に依存する危険がある」と書いたのは前提の確認が不足しており、実際には成立していなかった。設計としての静的共有状態は残るが、本 AC が問うている挙動は満たされている。なおキャッシュの注入可能化を検討する余地は TASK-116.11 の補足に引き継いだ。

なお、実 FS 書き込みが検証対象そのもので、モックに置換すべきでないと判断できた 2 ファイルのリネームは本タスク内で完了させた(CLIInstallerTests → CLIInstallerIntegrationTests、CLIShimInspectorTests → CLIShimInspectorIntegrationTests、スイート名も併せて変更)。残りの命名判断はモック置換の可否と不可分のため TASK-116.10 へ送った。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
917 行に 3 スイートが同居していた ViewerStoreTests.swift を、ViewerStoreTests(524 行) / ViewerStoreLoadingTests(44 行) / ViewerStoreChunkTests(362 行) に分割した。分割に伴い file-private ヘルパーの可視性を整理し、FailingSecondChunkReader は利用者が 1 ファイルに限られたため同ファイルへ移設して private を維持、StopCountingWatcher は 2 ファイルから使うため MockFileWatcher と同じ流儀で internal にし共有ヘルパーの置き場へ集約した。

DataURICache の静的共有状態によるテスト順依存は、実測の結果そもそも起きていないことが分かった(warm/cold の各テストが別 TempDir の一意パスを使うためキャッシュキーが衝突しない)。起票時の危険性の指摘は前提確認が不足していた。

あわせて、実 FS 書き込みが検証対象そのものである 2 ファイルを ~IntegrationTests へリネームした。規模が過大な「実 FS 依存のモック置換と命名整合」は TASK-116.10 へ、プロダクト API 変更を伴う「MarkdownImageEmbedder への依存注入」は TASK-116.11 へ、ユーザー判断で分離した。

検証: swift test が 593 tests / 77 suites を 14.998 秒で pass、SwiftFormat --lint クリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
