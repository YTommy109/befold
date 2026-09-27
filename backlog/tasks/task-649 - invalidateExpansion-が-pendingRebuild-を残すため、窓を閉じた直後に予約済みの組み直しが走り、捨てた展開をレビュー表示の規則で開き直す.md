---
id: TASK-649
title: >-
  invalidateExpansion が pendingRebuild
  を残すため、窓を閉じた直後に予約済みの組み直しが走り、捨てた展開をレビュー表示の規則で開き直す
status: To Do
assignee: []
created_date: '2026-09-27 08:37'
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
- [ ] #1 レビュー表示で子リストの着地により組み直しが予約された状態で `invalidateExpansion` を呼ぶと、予約済みの組み直しが走っても `childrenLister` が 1 回も発行されないテストがある
- [ ] #2 `invalidateExpansion` 後に `awaitSettled()` が待つものが無い（`pendingRebuild` が nil）
<!-- AC:END -->
