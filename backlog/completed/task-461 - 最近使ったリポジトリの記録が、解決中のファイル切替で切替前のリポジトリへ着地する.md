---
id: TASK-461
title: 最近使ったリポジトリの記録が、解決中のファイル切替で切替前のリポジトリへ着地する
status: Done
assignee: []
created_date: '2026-08-12 03:09'
updated_date: '2026-08-13 04:54'
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
- [x] #1 解決の着地時に、解決を開始した対象と現在の対象が一致することを確認してから repositoryRoot と記録を書く
- [x] #2 一致しない場合は記録も repositoryRoot の書き込みも行わない（次に開いた時点で記録されるため許容する、という既存の縮退方針に合わせる）
- [x] #3 解決の着地前にファイルが切り替わったケースを再現するユニットテストがあり、修正前に落ちることを確認している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
着地時の一致確認を RecentRepositoryRecorder.apply(root:identity:to:resolvedFor:) に追加した。解決を開始した url と controller.fileURL を normalizedPathKey で比較し、不一致なら repositoryRoot も store.record も行わない（既存の縮退方針どおり、次に開いた時点で記録される）。

単純化の検討: 「解決した root 配下に現在のファイルがあるか」で判定すれば同一リポジトリ内の切替でも記録を捨てずに済むが、入れ子リポジトリで誤って通る余地が増える。同一リポジトリ内切替で失うのは履歴 1 件だけで AC #2 の縮退方針に収まるため、述語を増やさず url の完全一致で判定した。

検証: befoldTests/ViewerWindowManagerRecentRepositoriesTests.swift に GatedGitFileIndex（対象ファイルの root 解決だけ semaphore で止める。上限は waitOrRecordTimeout）を追加し、解決を止めている間に /repoA/a.md → /repoB/b.md へ切り替えるテストを追加。修正行を外すと `(controller.repositoryRoot → file:///repoA) == nil` と entries 非空の 2 件で落ちることを実測（戻して再確認済み）。`swift test` 全体 1471 tests / 232 suites 通過。swiftlint はこの 2 ファイルで新規指摘なし（既存の type_name 警告のみ）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git ルート解決の着地時に、解決を開始したファイルとウィンドウの現在の表示ファイルが一致することを確認してから repositoryRoot と最近使ったリポジトリを書くようにした。解決中に別リポジトリのファイルへ切り替わるケースを止める。着地前切替の回帰テストを追加し、修正を外すと落ちることを確認、swift test 全体（1471 tests）通過。
<!-- SECTION:FINAL_SUMMARY:END -->
