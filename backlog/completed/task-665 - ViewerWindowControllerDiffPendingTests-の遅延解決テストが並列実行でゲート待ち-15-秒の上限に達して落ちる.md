---
id: TASK-665
title: ViewerWindowControllerDiffPendingTests の遅延解決テストが並列実行でゲート待ち 15 秒の上限に達して落ちる
status: Done
assignee:
  - '@claude'
created_date: '2026-09-29 07:52'
updated_date: '2026-09-29 08:47'
labels:
  - bug
  - test
dependencies: []
priority: medium
ordinal: 866000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
2026-09-29、TASK-662.6 の計測中に HEAD（6a81daaa）の `swift test`（並列）で 1 回落ちた（同じ日の並列 4 回中 1 回。直列では未観測）。

- 落ちたテスト: `ViewerWindowControllerDiffPendingTests.keepsResolvedDiffWhenBaseDirectoryResolutionLandsLate`
- 記録: `ViewerWindowControllerDiffPendingTests.swift` の `SlowRootGitFileIndex.repositoryRoot` で「同期待機が 15.0 秒で上限に達した」が 2 件（解決が 2 回呼ばれ、両方ゲートで塞がれている）
- 構造: TASK-662.5 で `Thread.sleep(0.5)` を `BlockingGate` へ置き換えた。ゲートは協調スレッドを同期に塞いだまま、テスト本体が `await controller.store.loadTask?.value` → `await controller.diffRefreshTask?.value` を終えて `gate.open()` に着くのを待つ。並列時は MainActor のキュー待ちで 1 回の配送が 10 秒級になる（TASK-662 の実測で passed after 35〜44 秒）ため、open に着く前に 15 秒の上限を超えうる

未確認: 上限超過が MainActor の混雑だけで説明できるか（塞がれた協調スレッド 2 本が loadTask 側の進行も止めている可能性）。落ちた回のサンプルは取れていない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 並列実行で落ちる条件（混雑だけか、塞いだ協調スレッドが待ち先の進行を止めているか）を特定している
- [x] #2 ゲートの上限を延ばす形ではなく、待ちの構造で直っている
- [x] #3 並列の全体実行で当該テストが 5 回連続緑
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 塞がれているスレッドの正体と、待ち先がゲートに依存しているかを実測で切り分ける
2. ゲートを同期の索引から async の境界(SidebarGitReading)へ移し、壁時計の上限を不要にする
3. TASK-512 の修正を外すと落ちること、混雑下で上限超過が出ないことを確認
4. 並列の全体実行 5 回
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因の特定(AC#1): 混雑だけで説明できる。協調スレッドは塞いでいない。
- 実測: LIBDISPATCH_COOPERATIVE_POOL_STRICT=1(プール幅 1)で当該スイートが 0.58 秒で通る。ゲートで止まる解決は SidebarGitReader.repositoryRootLookup → withBlockingWork の専用 Thread 上で走る(BefoldKit/BlockingWork.swift)ため、プールを消費しない
- コード参照: 2 件の上限超過は SidebarNavigator.init と SidebarListingCoordinator の baseDirectory.refresh() の 2 回ぶん。テストが open 前に待つ loadTask / diffRefreshTask はどちらも解決に依存しない(レンダリング表示なので refresh() は取得を起こさない)
- 再現: BEFOLD_TEST_TIMEOUT_SECONDS=0.3 で --filter ViewerWindowController を並列に回すと、同じ「上限に達した」が 2 件出る(テスト自体は 7.97 秒で pass、記録は «unknown» に付く)。open に着くまでが MainActor の順番待ちで決まり、同期ゲートの壁時計上限がそれを測っていた

修正(AC#2): ViewerWindowController に sidebarGit のテスト専用シームを足し、ゲートを AsyncGate として SidebarGitReading.repositoryRootLookup で止める。上限は無くなり、ハングはスイートの testTimeLimit が止める。同じ 0.3 秒・並列の条件で上限超過 0 件、テストは 7.93 秒で pass。settleDiffTestController の awaitSettled を外すと baseDirectory != nil で落ちることも確認済み

検証(AC#3): 並列の全体 swift test を 5 回連続で実行し、すべて exit 0。当該テストは 39.2〜39.9 秒で pass し、«unknown» の記録は 0 件。旧実装なら 15 秒の上限を超えていた待ちで、落ちる条件そのものの下で通っている
単純化の検討: 同期ゲートのまま上限だけを外す案は採らなかった。BlockingGate の上限は協調プールを守るための共有規約で、専用スレッドの場合だけ例外にすると規約が割れる。既存の async 境界(SidebarGitReading)は SidebarNavigator がもともと注入を受けているので、コントローラまで 1 引数を通すのが最小だった
lint: 触った 4 ファイルで swiftlint の警告は 0 件。途中の版で出た function_body_length / function_parameter_count は、既定値付きの引数を Assembler 側に置いて解消した。swiftformat の plugin を回しても追加の差分なし。check-type-group-size は閾値以内
responsibility-reviewer: High/Medium の指摘なし。Low が 1 件(gitFileIndex と sidebarGit を同時に渡すと、テストで食い違った状態を組める)。解消には全呼び出し元の変更が要り、flaky 修正の範囲を超えるため見送った
native-app-design.md への反映は不要(テスト専用シームの追加のみで、公開構成は変わらない)
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
並列実行で落ちていた原因は MainActor の混雑だけだった。ゲートの壁時計上限が、テスト本体が open に着くまでの順番待ちを測っていた。塞がれていたのは withBlockingWork の専用スレッドで、協調プールは消費していない(プール幅 1 で pass することを実測)。ViewerWindowController に sidebarGit のテスト専用シームを足し、ゲートを AsyncGate として async の境界へ移したので、上限そのものが不要になった。0.3 秒上限・並列の再現条件で超過 0 件、全体の並列実行 5 回連続で緑。TASK-512 の修正を外すとテストが落ちることも確認した
<!-- SECTION:FINAL_SUMMARY:END -->
