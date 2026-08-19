---
id: TASK-512
title: 差分系テストがサイドバーの基準ディレクトリ解決を待たず CI で断続的に落ちる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-18 01:08'
updated_date: '2026-08-18 01:43'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 741000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
差分系テストの準備ヘルパーが、構築時に飛ぶサイドバーの基準ディレクトリ解決タスクを待っていない。負荷の高いマシンでは、この解決が遅れて着地して確定済みの `.unavailable` を `.pending` へ戻し、直後の期待が落ちる。

## 事実（実測）

- 失敗は run 32041771129（PR #555 の build-and-test）の `ViewerWindowControllerDiffPendingTests.swift:58`。`Expectation failed: (controller.store.diffContent → .pending) == .unavailable`。落ちた期待は `await controller.diffRefreshTask?.value` の**後**にある。
- 分離実行（`swift test --filter ViewerWindowControllerDiffPendingTests`）は 5 回連続で 4 テストとも通り、所要は 0.55 秒。同じテストが CI では 45.1 秒かかって落ちている。
- ローカルの全体実行（`swift test`）は 4 回とも 0 failures。マシンが速く再現しない。
- 経路: `SidebarNavigator.swift:133` が init の末尾で `baseDirectory.refresh()` を呼ぶため、**コントローラ構築時に必ず解決タスクが飛ぶ**。着地時に `SidebarBaseDirectoryResolver.swift:66` が `host?.gitContextDidChange()` を呼び、`ViewerWindowController+SidebarHost.swift:31` の `refreshDiff()` へ届く。
- `ViewerDiffPresenter.refresh()` の未確定の立て方は `if case .diff = store.diffContent {} else { store.diffContent = .pending }` で、降格を防いでいるのは**確定差分を表示中のときだけ**。`.unavailable` は `.pending` へ戻る。これは意図した挙動（新しい取得が実際に飛んでいる）で、製品側のバグではない。
- 決定的な再現: 使い捨てテストで、取得着地後に `controller.gitContextDidChange()` を 1 回明示的に呼ぶだけで CI と同一文言で落ちることを確認した（`after fetch: unavailable` → `after gitContextDidChange: pending`）。
- `preparePresentedMarkdown`（ViewerWindowControllerDiffPendingTests.swift:117）と `presentDocument`（DiffTestSupport.swift:85）はどちらも `store.loadTask` しか待っておらず、サイドバー側の in-flight タスクを待っていない。
- `awaitSettled()` を使っているテストファイルは 10 本以上あるのに対し、差分系の 3 ファイル（DiffPendingTests / DiffTests / DiffTestSupport）だけが使っていない。

## 同型の 3 回目である

TASK-437 が壁時計予算の限界を結論し差分取得側を await task へ移行、TASK-509 が残りのコンテンツロード待機を `store.loadTask` の await へ移した。今回はその両方が塞いだのとは別の in-flight タスク（サイドバーの基準ディレクトリ解決）が同じ形で残っていたもの。CLAUDE.md の「同型のバグが 2 回目に出たら個別修正をやめて構造で塞ぐ」に該当するため、テストごとに待機を足す対処は採らない。

## 方針

新しい待ち合わせを作らず、既存の共有シーム `SidebarNavigator.awaitSettled()`（3 つの in-flight タスクをまとめて待つために存在する）を、差分系の**共有ヘルパー側**で通す。テスト個別に await を足す形にはしない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 差分系テストの準備ヘルパー（preparePresentedMarkdown / presentDocument）を通ったあと、サイドバーの in-flight タスクが残らない
- [x] #2 待ち合わせは既存の SidebarNavigator.awaitSettled() を共有ヘルパー側で通す形になっており、テスト個別に await を足していない
- [x] #3 取得着地後に gitContextDidChange() が起きても最終状態が壊れないことを固定するテストがあり、修正を戻すと落ちることを実測で確認している
- [x] #4 befoldTests 全体を確認し、サイドバーの in-flight タスクを待たずに差分・表示状態を検証している箇所が他に残っていない（残す場合は理由を Implementation Notes に書く）
- [x] #5 swift test がローカルで通る（失敗ゼロ、テスト名まで確認する）
- [ ] #6 main へマージ後の thread-sanitizer ジョブが通ることを確認する（PR では走らないため、マージ後の run を必ず見る）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 差分系の共有ヘルパー(DiffTestSupport)に settleDiffTestController を置き、loadTask → sidebar.awaitSettled() → diffRefreshTask をこの順で待ち切る
2. presentDocument / preparePresentedDocument をこのヘルパー経由の async にし、テスト個別の await を撤去する
3. 合流検証(2 窓)のために複数コントローラを同一ターンで提示する presentDocument(in:[controller]) を用意する
4. 基準ディレクトリ解決が準備を抜けた時点で着地していることを固定する回帰テストを DiffPendingTests に足す
5. befoldTests 全体を監査し、サイドバーの in-flight を待たずに測っている箇所が残っていないか確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装

- `DiffTestSupport.settleDiffTestController(_:)` を新設し、`store.loadTask` → `sidebar.awaitSettled()` → `diffRefreshTask` の順で待ち切る。`preparePresentedDocument(in:file:)` / `presentDocument(in:file:)` がこれを通す（テスト個別の await は撤去した）。
- `presentDocument(in:[ViewerWindowController],file:)` を追加。**提示は全窓ぶんを同じターンで**行ってから待つ。GitDiffLoader の畳み込みは「同じ契機（1 ターン）から出た要求」だけを合流させる契約のため、1 窓ずつ提示して待ち切ると兄弟要求が別ターンへ散り、`sharesOneFetchAcrossWindowsShowingTheSameFile` が成立しなくなる（実測: 1 窓ずつ待つ実装では `texts[0] == .diff("取得3")` / `texts[1] == .pending` で落ち、その前段の待ちが 60 秒で打ち切られた）。
- `presentDocument` の待ちは表示モードを `.diff` にした**後**に行う。切替そのものが取得を起こすため。

## 検証

- AC#3: `keepsResolvedDiffWhenBaseDirectoryResolutionLandsLate` を追加（`SlowRootGitFileIndex(delay: 0.5)` でルート解決を遅らせ、準備を抜けた時点で `fileListModel.baseDirectory` が確定していることを固定）。共有ヘルパーの `awaitSettled()` を外して実測すると `Expectation failed: (controller.fileListModel.baseDirectory → nil) != nil` で落ちる。
- AC#5: `swift test` を 2 回実行し、いずれも 1608 tests / 255 suites で失敗ゼロ。差分系のみの `--filter Diff` は 3 回連続で 86 tests 通過。
- swiftlint は origin/main を `git archive` で展開したツリーと比較し、正規化後の差分ゼロ（54 件で一致）。swiftformat は要整形ゼロ。

## AC#4 の監査結果（差分系 4 ファイル以外は該当ゼロ）

`gitContextDidChange()` の着地で変わりうるのは `store.diffContent`（ViewerDiffPresenter.refresh）と、`fileListModel.baseDirectory` が nil → `.plainFolder` へ確定することによる `capabilities.canSelect(.diff)` の 2 つ。全テストが `@MainActor` で着地は MainActor へのホップなので、**テスト関数が同期（await 無し）なら着地は割り込めない**。

残すもの（理由つき）:

- `ViewerWindowStateIndependenceTests.swift:60,:177` / `ViewerWindowControllerSourceModeTests.swift:101,:155,:174,:198,:222` … `setDisplayMode(.diff)` を含むがすべて同期テスト。将来これらに `await` を 1 行足すと同じ形で落ちうる（`setDisplayMode(.diff)` が `canSelect` ガードで無音の no-op になる経路のため）。
- `ViewerWindowControllerToolbarTests.swift:253` … `canSelect(.diff)` を見るが、直前で `sidebar.awaitSettled()` 済み。
- `ViewerWindowControllerGitStatusTests.swift:40` … `pendingGitStatusTask` を明示的に待ち、検証対象は `fileListModel.gitStatus`。
- Integration 系（`ViewerWindowControllerIntegrationTests` / `ViewerWindowManagerIntegrationTests` / `ViewerWindowManagerDisplayOverridesIntegrationTests`）… すでに `awaitSettled()` を呼んでいる。

## AC#6

PR では thread-sanitizer ジョブが走らないため未確認。**main へマージ後の run を必ず見ること**（このタスクの唯一の残作業）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
差分系テストの待ち合わせを共有ヘルパー(DiffTestSupport.settleDiffTestController)へ寄せ、既存の SidebarNavigator.awaitSettled() を通すようにした。テスト個別の await は足していない。基準ディレクトリ解決が準備を抜けた時点で確定していることを固定する回帰テストを追加し、待ち合わせを外すと落ちることを実測で確認。swift test は 2 回とも 1608 件失敗ゼロ、swiftlint は main とのベースライン差分ゼロ。thread-sanitizer(AC#6)はマージ後の run で確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
