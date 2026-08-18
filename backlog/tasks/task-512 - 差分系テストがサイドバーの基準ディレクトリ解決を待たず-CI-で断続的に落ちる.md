---
id: TASK-512
title: 差分系テストがサイドバーの基準ディレクトリ解決を待たず CI で断続的に落ちる
status: To Do
assignee:
  - '@claude'
created_date: '2026-08-18 01:08'
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
- [ ] #1 差分系テストの準備ヘルパー（preparePresentedMarkdown / presentDocument）を通ったあと、サイドバーの in-flight タスクが残らない
- [ ] #2 待ち合わせは既存の SidebarNavigator.awaitSettled() を共有ヘルパー側で通す形になっており、テスト個別に await を足していない
- [ ] #3 取得着地後に gitContextDidChange() が起きても最終状態が壊れないことを固定するテストがあり、修正を戻すと落ちることを実測で確認している
- [ ] #4 befoldTests 全体を確認し、サイドバーの in-flight タスクを待たずに差分・表示状態を検証している箇所が他に残っていない（残す場合は理由を Implementation Notes に書く）
- [ ] #5 swift test がローカルで通る（失敗ゼロ、テスト名まで確認する）
- [ ] #6 main へマージ後の thread-sanitizer ジョブが通ることを確認する（PR では走らないため、マージ後の run を必ず見る）
<!-- AC:END -->
