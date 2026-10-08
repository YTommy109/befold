---
id: TASK-353.3
title: サイドバーの git バッジを窓の比較基準に追従させる
status: In Progress
assignee:
  - '@claude'
created_date: '2026-10-08 02:00'
updated_date: '2026-10-08 04:52'
labels: []
milestone: m-11
dependencies:
  - TASK-353.2
parent_task_id: TASK-353
priority: medium
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 背景

TASK-352 で、差分ビューアとサイドバーのバッジの基準を `GitComparisonBase` に統一した（バッジは変更ありなのに差分が空、という食い違いを解消した）。TASK-353.2 で差分の基準を窓ごとに切り替えられるようにすると、バッジが固定のままでは同じ食い違いが別の形で戻る。

現状のバッジは 2 系統（`GitStatusReader.status(forRepositoryAt:)`）: 作業ツリーの staged / unstaged / untracked と、`branchChanges(in:base:)` による base..HEAD の「ブランチで変更」。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 「このブランチの変更」「スタック全体の変更」では、ブランチで変更のバッジがその基準..HEAD の範囲に付く
- [x] #2 「作業中の変更」では、ブランチで変更のバッジを出さない
- [x] #3 「変更のみ表示」の絞り込みも同じ基準に従う
- [x] #4 基準を切り替えたときにバッジが再計算される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## /review-design の結果（2026-10-08）

353.1 / 353.2 の設計を取ると、このタスクで新しく書くものはほぼ無い。実装前に次を確かめ、足りないものだけ足す。

- AC#1: `GitStatusReader.status(forRepositoryAt:target:)` が 353.2 で target を受けるので、`branchChanges(in:base:)` に渡る base が target の解決結果になる。新しい分岐は無い
- AC#2: `.head` は base = HEAD で `git_diff_tree_to_tree(HEAD, HEAD)` が空になる。**「作業中なら branchChanges を飛ばす」という if を足さない**（チェック 1: 事実で判定。特別扱いを足すと 3 基準目で同型の穴が出る）
- AC#3: 絞り込みは `SidebarGitStatus.hasChange(at:)` がバッジの引き当てに委ねている（TASK-345）ので、スナップショットが基準に追従すれば自動で揃う。新コード無し。テストは `SidebarChangedFilesOnlyIntegrationTests` に target 引数のケースを 1 つ足す
- AC#4: 353.2 の `setComparisonTarget → refreshGitStatuses(.always)` が再計算の契機。ここで確かめるのは、`GitStatusStore` の `.onlyIfIndexChanged` キャッシュが target 違いで再利用されないこと（353.2 のテスト）と、`FileListGitStatusGate` が旧 target のスナップショットを捨てること
- `SidebarNavigator`（425/425）と `FileListModel`（400/400）は余裕ゼロ。どちらにも行を足さない。足す必要が出たらこのタスクで分割せず、設計へ戻る
- 空状態の文言（"No Changed Files"）は 3 基準とも事実と一致するので変えない
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
新コードなし。AC#1〜#4 は 353.2 の経路(GitStatusReader.status(target:) → branchChanges(base:)、setComparisonTarget → refreshGitStatuses(.always)、SidebarGitStatus.hasChange)で成立していることをコードと実 git のテストで確認した。「作業中なら branchChanges を飛ばす」分岐は足していない(.head は base..HEAD が空になる帰結)。追加テスト: SidebarChangedFilesOnlyIntegrationTests に target 別 3 件(defaultBranch で残る / head で空 / 切替後に取り直し)。FileListGitStatusGate 自体は target を知らない。旧 target のスナップショットを捨てるのは SidebarGitStatusCoordinator.apply の request.target 照合で、SidebarNavigatorGitStatusTests.discardsStatusesFetchedUnderOldTarget で担保(照合を外すと落ちることを確認)。Reader が target を無視する変異でも 3 件 + AC#5 のテストが落ちる。全 swift test 2032 件 pass(既知 known issue 1 件は BlockingWaitTests)、swiftformat --lint ゼロ、swiftlint は変更ファイルに指摘なし、xcodebuild build 成功。
<!-- SECTION:NOTES:END -->
