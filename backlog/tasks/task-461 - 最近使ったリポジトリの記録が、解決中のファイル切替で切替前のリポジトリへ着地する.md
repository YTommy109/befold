---
id: TASK-461
title: 最近使ったリポジトリの記録が、解決中のファイル切替で切替前のリポジトリへ着地する
status: To Do
assignee: []
created_date: '2026-08-12 03:09'
labels: []
dependencies: []
priority: low
type: bug
ordinal: 685000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RecentRepositoryRecorder.recordIfNeeded(for:controller:) は git ルート/identity の解決を detached タスクへ逃がし、結果を MainActor 上の apply(root:identity:to:) で反映する。このとき見ているのはコントローラが生きているか（weak controller が nil でないか）だけで、**解決を始めた時点の対象と着地時の対象が一致しているかを確認していない**。

ウィンドウはコントローラを保ったままファイルを切り替える（ViewerWindowControllerDelegate.viewerWindow(_:didSwitchFileFrom:to:)）。解決が終わる前に別リポジトリのファイルへ切り替わると、controller.repositoryRoot に切替前のリポジトリのルートが書かれ、その後そのウィンドウを閉じる/アクティブ化するたびに recordTabGroup が誤ったリポジトリのタブ構成として記録する。

TASK-459（ViewerWindowManager の分割）の実装前設計レビューで検出した。同タスクでは責務を移しただけで判定は一切変えていないため、この挙動は分割前から存在する。

.claude/CLAUDE.md の「非同期で置き換わる表示状態の世代管理」でいう**着地時の一致確認**の欠落にあたる（開始時の無効化は、記録が 1 件増えないだけなので不要と判断してよい）。

## 確認方法（未実施）

git 管理下の 2 つの異なるリポジトリ A / B を用意し、A のファイルでウィンドウを開いた直後（解決が着地する前）にサイドバーから B のファイルへ切り替える。ViewerWindowManagerRecentRepositoriesTests の FixedRootGitFileIndex を「解決に遅延を挟む索引」へ差し替えれば、実 git なしで再現できる見込み。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 解決の着地時に、解決を開始した対象と現在の対象が一致することを確認してから repositoryRoot と記録を書く
- [ ] #2 一致しない場合は記録も repositoryRoot の書き込みも行わない（次に開いた時点で記録されるため許容する、という既存の縮退方針に合わせる）
- [ ] #3 解決の着地前にファイルが切り替わったケースを再現するユニットテストがあり、修正前に落ちることを確認している
<!-- AC:END -->
