---
id: TASK-649
title: >-
  invalidateExpansion が pendingRebuild
  を残すため、窓を閉じた直後に予約済みの組み直しが走り、捨てた展開をレビュー表示の規則で開き直す
status: Done
assignee:
  - '@claude'
created_date: '2026-09-27 08:37'
updated_date: '2026-09-27 08:44'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/SidebarTreePresenter.swift
  - BefoldApp/befoldTests/SidebarNavigatorReviewExpansionTests.swift
priority: medium
ordinal: 849000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 経緯

`/code-review high`（2026-09-27、TASK-645〜648 の後）の指摘。コードで裏を取った。TASK-645（lastReveal の残り）と同型で、`invalidateExpansion` が捨て損ねている寿命がもう 1 つある。

## 現状（検証済み）

- `invalidateExpansion` は `expansion.invalidateAll()` / `childTasks.removeAll()` / `lastReveal = nil` を行うが、`pendingRebuild` はそのまま（`SidebarTreePresenter.swift` の `invalidateExpansion`）。
- `loadChildren` の Task は `expansion.apply` が券を拒否した場合でも `scheduleRebuild()` を呼ぶ。つまり無効化済みの取得が着地しても組み直しが予約される。
- 予約された Task は次のメインアクター実行で `rebuildRows` → `applyRows` → `revealChangedFolders` を通る。`display` / `gitStatus` / `currentDirectory` は変わっておらず `lastReveal` は nil なので、候補を全件数え直して `expandFolder` を全対象に発行する。

## 再現の形

レビュー表示（ツリー × 変更のみ）で子リストが着地して `scheduleRebuild` が予約された同じ実行ターンで窓を閉じる（`cancelPendingListing` → `invalidateExpansion`）。予約済みの Task が走り、存在しない窓のために N フォルダーの `childrenLister` が発行される（各 Task は self を強参照するので、遅いボリュームでは全取得のタイムアウトまで presenter / FileListModel が生き残る）。

## 方向

`invalidateExpansion` で `pendingRebuild` も捨てる（cancel + nil）。Task 本体は `Task.isCancelled` か「自分がまだ `pendingRebuild` か」を見て組み直しを飛ばす。TASK-645 と同じく「invalidateExpansion が捨てる寿命」を 1 箇所に揃える。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 レビュー表示で子リストの着地により組み直しが予約された状態で `invalidateExpansion` を呼ぶと、予約済みの組み直しが走っても `childrenLister` が 1 回も発行されないテストがある
- [x] #2 `invalidateExpansion` 後に `awaitSettled()` が待つものが無い（`pendingRebuild` が nil）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. invalidateExpansion で pendingRebuild を cancel + nil にし、Task 本体は取り消し済みなら pendingRebuild に触れず返る
2. 単純化: loadChildren は apply が拒否した着地では組み直しを予約しない(拒否された券は材料を変えず、無効化した側が行を扱う)。これで無効化後の古い着地が予約を作り直す経路も消える
3. SidebarTreePresenterChildTasksTests に 2 経路(予約済み→破棄 / 破棄→古い着地)のテストを足す
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化の検討: 方向どおり pendingRebuild を捨てるだけでは、展開を捨てた後に走行中の取得が着地すると(apply は拒否)scheduleRebuild が予約を作り直し、同じバグが再発する。拒否された着地での組み直し自体が不要(畳みは同期で組み直し済み・取り直しは新しい券の着地が組み直す・破棄は呼び出し側が行を扱う)なので、予約を着地の受理時だけに絞った。
検証: 修正前のプロダクトコードで追加 2 テストがともに失敗(hasPendingRebuild / issued==2 / expandedKeys 非空)、修正後に成功。swift test 全件成功(2009 + 72)。/swiftlint-baseline 新規 0。
docs: viewer-ui.md の「組み直しをまとめる」記述は変わらないため更新不要。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
invalidateExpansion が予約済みの組み直し(pendingRebuild)も取り消すようにし、子リストの着地が拒否された場合は組み直しを予約しないようにした。窓を閉じた・ルートを切り替えた直後に、捨てた展開がレビュー表示の規則で開き直され childrenLister が発行される経路が 2 つとも塞がる。SidebarTreePresenterChildTasksTests に 2 テストを追加(修正前は失敗を確認)。swift test 全件成功、swiftlint の main 差分ゼロ。
<!-- SECTION:FINAL_SUMMARY:END -->
