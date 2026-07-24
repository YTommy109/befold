---
id: TASK-116.9
title: テストコードに混入したタスク番号・issue 番号の参照を除去する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 23:20'
updated_date: '2026-07-24 00:47'
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
- [x] #1 テストコードのコメント・@Test 表示名にタスク番号/issue 番号/PR 番号が含まれていない
- [x] #2 テストフィクスチャのファイル名にタスク番号が含まれていない
- [x] #3 番号を削除した箇所で、検証意図が振る舞いの説明として読み取れる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
62 箇所を処理した。機械的に消せるもの(@Test 表示名の末尾に付いた (TASK-xxx) / (task-xxx))は 25 箇所を一括除去。残る 37 箇所は番号が文脈を担っていたため、番号を消すだけでなく振る舞いの説明として読めるよう書き換えた。主なもの:

- CLIInstanceRouterTests: 「この2ケースを true 扱いすることは task-86 で検討済みで、意図的に許容している既知の限界」→「検討の上で意図的に許容している既知の限界」
- StringChunkReaderTests: 「500 バイト回復機能(TASK-57)導入後は」→「500 バイト回復機能の導入後は」
- ViewerStoreTests: 「正常な EOF との区別が TASK-25 の狙い」→「正常な EOF と区別することが狙い」
- ViewerBridgeTests: 「TASK-1.12 で viewer.html のインライン <script> を CSP から外部化したため」→「インライン <script> は CSP の script-src から unsafe-inline を除去するために viewer-main.js へ外部化したため」
- ViewerStoreFileTypeConsistencyTests: 内容が重複していた「(TASK-23 の回帰なし)」の行は、直前の説明で意図が伝わるため削除
- FileListViewTests: 「(#142 の回帰テスト)」→「(回帰テスト)」、「問題(#142)の回帰テスト」→「問題の回帰テスト」
- MARK コメント 3 箇所の (TASK-1.11) / (TASK-1.12) / TASK-70: を除去

フィクスチャ名も改名した: task-1-11-oneshot.log/.md → oneshot.log/.md、task-1-11-default.log → default-load.log、task-70-warm.png → warm.png、task-70-cold.png → cold.png(参照している Markdown 本文側も併せて更新)。

作業中のミス: ViewerBridgeTests の書き換えで置換文字列のクォートが .unsafe-inline. になってしまっていたのを検出し、\x27unsafe-inline\x27 に戻した。

検証: grep で TASK- / task- / PR # / #1xx の参照が befoldTests・befoldCLITests から 0 件になったことを確認。swift test が 593 tests / 77 suites を 14.354 秒で pass。SwiftFormat --lint は全ターゲットでクリーン。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
テストコードに混入していたタスク番号・issue 番号・PR 番号の参照 62 箇所を除去した。@Test 表示名末尾の純粋な付記 25 箇所は一括除去し、番号が文脈を担っていた 37 箇所は「なぜこの挙動を検証しているのか」が読み取れる説明に書き換えた(単に番号を消すと意図が失われるため)。フィクスチャ名に埋め込まれていた task-1-11-* / task-70-* も改名した。

検証: grep で該当参照が 0 件になったことを確認。swift test が 593 tests / 77 suites を 14.354 秒で pass、SwiftFormat --lint クリーン。
<!-- SECTION:FINAL_SUMMARY:END -->
