---
id: TASK-116.9
title: テストコードに混入したタスク番号・issue 番号の参照を除去する
status: To Do
assignee: []
created_date: '2026-07-23 23:20'
labels:
  - test
  - cleanup
  - docs
dependencies: []
parent_task_id: TASK-116
priority: low
ordinal: 30900
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
`docs/dev/coding_rule.md:454-458` は「タスク番号や変更履歴の参照(コミットメッセージに書く)」をコメントに書かないと定め、**`@Test("...")` の表示名にも等しく適用する**と明記している。約 60 箇所が違反している。

## @Test 表示名への混入(最も目立つ)

BefoldApp/befoldTests/ 配下:
- CLICheckCommandTests.swift:67(TASK-73.8) / :98(TASK-73.12, TASK-80)
- TextEncodingTests.swift:45(task-31) / :67(task-36) / :76(task-47) / :85(task-47) / :95(task-36)
- ViewerStoreTests.swift:538(task-30) / :739(TASK-39) / :772(TASK-45) / :895(TASK-41)
- BookmarkStoreTests.swift:24 / :33(TASK-73.4) / :102(TASK-111)
- ViewerWindowManagerTests.swift:368(TASK-73.3) / :385 / :408(TASK-73.2)
- ViewerWindowControllerCLIOptionsTests.swift:88(TASK-73.13) / :123(TASK-77)
- CLIInstanceRouterTests.swift:70(task-81)
- DirectoryListerTests.swift:338(TASK-80)
- FileListViewTests.swift:44 / :102(#142)

BefoldApp/befoldCLITests/ 配下:
- CLICheckAndBookmarkDefaultsTests.swift:7(`///` に TASK-110/TASK-111) / :10(TASK-110) / :23(TASK-111)

## /// ・// MARK: ・インラインコメントへの混入

ViewerRendererContentUpdateTests.swift:6(TASK-68) / :87(PR #262)、ViewerBridgeTests.swift:273,:308,:321(TASK-1.12)、ViewerLoadPipelineTests.swift:6,:79、NormalizedTextCacheTests.swift:174、NormalizedTextCacheLazyGrowthTests.swift:6、SessionRestorerTests.swift:7、CLIRequestDeduplicatorTests.swift:4、SidebarNavigatorIntegrationTests.swift:103、ViewerStoreFileTypeConsistencyTests.swift:11,:40,:62,:96、StringChunkReaderTests.swift:119、ViewerWindowManagerDisplayOverridesTests.swift:6、ViewerWebViewCoordinatorTests.swift:162、DirectoryListerTests.swift:6、ViewerWindowControllerCLIOptionsTests.swift:6、CLIInstanceRouterTests.swift:7,:69、ViewerStoreTests.swift:533,:726、ViewerRendererOneShotTests.swift:6、ViewerStoreFileGoneTests.swift:121

## ファイル名・パスへの埋め込み

ViewerLoadPipelineTests.swift:16,:38,:60,:99,:100,:115,:127,:128,:140 が `/tmp/task-1-11-oneshot.log` / `task-70-warm.png` のようにタスク番号をフィクスチャ名に埋め込んでいる。同じ理由で `oneshot.log` / `warm.png` 等へ改名する。

## 注意

番号を消すだけでなく、その番号が担っていた文脈(なぜこの挙動を検証しているのか)が失われる場合は、番号の代わりに**振る舞いの説明**に置き換えること。単なる削除で意図が不明になるなら本末転倒。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 テストコードのコメント・@Test 表示名にタスク番号/issue 番号/PR 番号が含まれていない
- [ ] #2 テストフィクスチャのファイル名にタスク番号が含まれていない
- [ ] #3 番号を削除した箇所で、検証意図が振る舞いの説明として読み取れる
<!-- AC:END -->
