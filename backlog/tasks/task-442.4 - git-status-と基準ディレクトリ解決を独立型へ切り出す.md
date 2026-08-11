---
id: TASK-442.4
title: git status と基準ディレクトリ解決を独立型へ切り出す
status: To Do
assignee: []
created_date: '2026-08-11 07:35'
labels: []
dependencies:
  - TASK-442.3
parent_task_id: TASK-442
ordinal: 676000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator から git 関心を 2 つの独立型へ出す。1 つにまとめない理由は、性質の違う 2 つの非同期関心だから。基準ディレクトリ解決の書き込み先は fileListModel.baseDirectory (相対パスコピー・Quick Open のヘッダー表示) で、git バッジ経路 (fileListModel.applyGitStatus → .git/index 監視 → host.gitStatusDidApply) とは別。resolveGitRoot の唯一の呼び出し元は refreshBaseDirectory であり、git status 側は resolveGitRoot を必要としない。

(A) SidebarBaseDirectoryResolver: resolveGitRoot / baseDirectoryGeneration / pendingBaseDirectoryTask / refreshBaseDirectory()
(B) SidebarGitStatusCoordinator: loadGitStatuses / makeGitIndexWatcher / gitIndexWatch / gitStatusGeneration / pendingGitStatusTask / refreshGitStatuses(policy:) / applyGitStatus / awaitingCancellable / performListing の git 側待ち合わせ

(B) の設計上の要点。

- 反映通知はクロージャ注入にせず、既存の SidebarNavigatorHost を weak で直接持つ。gitStatusDidApply() は「バッジと差分の更新契機を 1 つにする」判断をコンパイル時に守らせるための必須メソッド (SidebarNavigator.swift:16-22 / TASK-330) であり、クロージャを 1 段挟むとその意図が薄まる。host は super.init 後にしか渡せないため attach(to:) で結線する。
- 世代を型の外へ漏らさない。現在 gitStatusGeneration は 3 箇所 (単発取得 :152 / 一覧との結合取得 :253 / 一括無効化 :313) で進んでおり、採番点を型の内側 1 つに閉じることがこの分割の実質的な利得。採番済み sequence を持つ「券」を返す API にして、performListing は券を受け取るだけにする。
- 分離できたかの判定基準: cancelPendingListing の git 関連 4 行 (世代加算 / invalidatePendingGitStatus / pendingGitStatusTask.cancel / gitIndexWatch.stop) が coordinator の 1 メソッド呼び出しへ畳めること。畳めないなら分離できていない。
- TASK-293/294/297 の不変条件を壊さないこと。絞り込み ON のときは一覧と git 結果を同一 Task・同一メインアクター実行で反映し、OFF のときは分ける。反映の可否判定 (recency + ディレクトリ対付け) は従来どおり FileListModel.applyGitStatus(_:for:sequence:) に置いたままにする (ADR 0003)。
- テストの観測点 pendingGitStatusTask / pendingBaseDirectoryTask は約 30 箇所ある。互換用の委譲プロパティは残さない (本体に git 側 stored への参照が残ると上の判定基準が使えなくなる)。テスト側を新型へ向け直す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 基準ディレクトリ解決と git status 取得がそれぞれ独立型へ切り出され、resolveGitRoot は基準ディレクトリ側だけが持つ
- [ ] #2 git status 側の反映通知が SidebarNavigatorHost の weak 参照であり、そのためのクロージャ注入が無い
- [ ] #3 gitStatusGeneration に相当する採番が新型の内側だけで行われ、SidebarNavigator は sequence を読み書きしない
- [ ] #4 cancelPendingListing の git 関連処理が新型の 1 メソッド呼び出しへ畳まれている
- [ ] #5 絞り込み ON で一覧と git 状態が同一メインアクター実行で反映されることを担保する既存テスト (SidebarNavigatorListingCoherenceTests) が通る
- [ ] #6 SidebarNavigator への注入クロージャが 3 個以下になっている
- [ ] #7 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->
