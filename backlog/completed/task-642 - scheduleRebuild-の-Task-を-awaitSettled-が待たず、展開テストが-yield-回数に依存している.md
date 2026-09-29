---
id: TASK-642
title: scheduleRebuild の Task を awaitSettled が待たず、展開テストが yield 回数に依存している
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 06:23'
updated_date: '2026-09-27 06:58'
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
- [x] #1 `awaitSettled()` の後に `entries` を読んでも、予約中の行の組み直しが未反映であることがない（rebuild Task が待ち合わせに含まれる）
- [x] #2 `SidebarNavigatorExpansionTests` の `Task.yield()` ループが `awaitSettled()` に置き換わり、同じ形の待ちを持つサイドバー系スイートを洗って同様に直しているか、直さない理由を Notes に残している
- [x] #3 `SidebarNavigatorReviewExpansionTests.settle()` の 2 回呼びが解消されているか、2 回目が何を待っているかがコメントで説明されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarTreePresenter が子リスト取得 Task(pathKey ごと)と予約中の組み直し Task を持ち、awaitSettled() で両方が空になるまで待つ
2. SidebarNavigator.awaitSettled() の末尾で tree.awaitSettled() を待つ
3. サイドバー系テストの yield ループを awaitSettled() へ置き換え、settle() の 2 回呼びを 1 回にする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
- isRebuildScheduled は pendingRebuild(Task?) に置き換えた(フラグとハンドルの二重持ちを避ける)。本体は同期なので走り始めに nil へ戻しても観測されない。
- 子リスト Task は invalidateExpansion / collapseFolder で外す。無効化済みの取得を待つと、ゲートで止めたままの古い取得(rootSwitchDiscardsInFlightExpansion 等)にテストが引っかかるため。
- 組み直しがレビュー表示の規則を通って次の展開を始めうるので、presenter 側は子リストと組み直しが両方空になるまでループする。
- 置き換えたスイート: SidebarNavigatorExpansionTests / SidebarLayoutTransitionTests(drainChildLoads は awaitSettled 1 行になったので撤去) / SidebarPostSwitchSyncTests / SidebarNavigatorSyncAfterSwitchTests。SidebarNavigatorListingCoherenceTests の yield はスタブ内で git の遅延を模すためのもので待ち合わせではないので対象外。gate 解放前に 1 回だけ譲る Task.yield()(ExpansionTests の 2 箇所)は、取得を走行中にしておくための意図した譲りなので残した。
- SidebarLayoutTransitionTests の選択行スクロール検証は、SidebarTableFocuser が DispatchQueue.main.async で遅らせるため awaitSettled の対象外。置き換え直後に 6 回中 3 回落ちた(spy.scrolledRows.last が 0)。FileListModelScrollTests と同じ drainMainQueue() を置いて解消。
- settle() の 2 回呼びは 1 回へ。Review/Expansion/LayoutTransition/PostSwitchSync/SyncAfterSwitch の 5 スイート 27 件を 15 回連続実行して全緑。
- 検証: swift test 全 2001 件緑、swiftlint の main との差分ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigator.awaitSettled() が展開したフォルダーの子リスト取得と、その着地が予約した行の組み直しまで待つようにした(presenter が Task ハンドルを持ち、無効化時に外す)。サイドバー系 4 スイートの yield ループを awaitSettled() へ置き換え、ReviewExpansion の settle() は 1 回に。対象 5 スイートを 15 回連続実行・全テスト 2001 件で検証。
<!-- SECTION:FINAL_SUMMARY:END -->
