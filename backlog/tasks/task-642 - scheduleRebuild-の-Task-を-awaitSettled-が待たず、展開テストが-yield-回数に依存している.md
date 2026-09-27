---
id: TASK-642
title: scheduleRebuild の Task を awaitSettled が待たず、展開テストが yield 回数に依存している
status: To Do
assignee: []
created_date: '2026-09-27 06:23'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befold/App/SidebarNavigator.swift
  - BefoldApp/befoldTests/SidebarNavigatorExpansionTests.swift
  - BefoldApp/befoldTests/SidebarNavigatorReviewExpansionTests.swift
priority: low
type: task
ordinal: 842000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

TASK-637（commit c1de117a）で、子リスト着地ごとの行の全組み直しを 1 回へまとめる `SidebarTreePresenter.scheduleRebuild` を入れた（400 フォルダーで 3.8 秒 → 80ms）。`/code-review high` の指摘を検証したところ、テスト側の待ち合わせに穴があることを確認した。

## 現状（検証済み）

- `scheduleRebuild` は追跡されない unstructured Task で行を組み直す。`SidebarNavigator.awaitSettled()` が待つのは `pendingListingTask` / `pendingGitStatusTask` / `pendingBaseDirectoryTask` の 3 つだけで、子リストの Task もこの rebuild Task も待たない。
- `SidebarNavigatorExpansionTests` は `for _ in 0 ..< 10 { await Task.yield() }` の後に `entries` を読む。この commit でメインアクターのホップが 1 つ増えたので、必要ホップ数（2〜3）に対する余裕は減った。CI 負荷次第で `entries` に子行が無いまま assert に到達しうる。同じ形で `entries` を読む可能性のあるスイート: `SidebarLayoutTransitionTests` / `SidebarPostSwitchSyncTests` / `SidebarNavigatorSyncAfterSwitchTests`（未追跡）。
- 新設の `SidebarNavigatorReviewExpansionTests.settle()` は `awaitSettled()` を 2 回呼んでいるが理由のコメントが無い。2 回目は `onGitStatusChange` や切替経路が後から始める `gitStatus.refresh` を拾っているとみられる。このスイート自体は `expandedFolderKeys`（`beginExpanding` で同期的に書かれる）しか assert しないので、rebuild のホップには依存しない。

## 方向

presenter が予約中の rebuild Task のハンドルを持ち、`awaitSettled` がそれも待つようにする（テスト専用フックを増やすより、既存の待ち合わせ点に合流させる）。yield ループで待っている既存テストは `awaitSettled` に寄せる。`settle()` の 2 回呼びは理由を書くか、1 回で済む形にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 `awaitSettled()` の後に `entries` を読んでも、予約中の行の組み直しが未反映であることがない（rebuild Task が待ち合わせに含まれる）
- [ ] #2 `SidebarNavigatorExpansionTests` の `Task.yield()` ループが `awaitSettled()` に置き換わり、同じ形の待ちを持つサイドバー系スイートを洗って同様に直しているか、直さない理由を Notes に残している
- [ ] #3 `SidebarNavigatorReviewExpansionTests.settle()` の 2 回呼びが解消されているか、2 回目が何を待っているかがコメントで説明されている
<!-- AC:END -->
