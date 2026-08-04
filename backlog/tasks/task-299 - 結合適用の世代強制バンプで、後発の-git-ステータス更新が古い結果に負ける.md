---
id: TASK-299
title: 結合適用の世代強制バンプで、後発の git ステータス更新が古い結果に負ける
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 16:34'
updated_date: '2026-08-04 23:29'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: high
type: bug
ordinal: 100000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の CONFIRMED 指摘。TASK-294 の修正で、SidebarNavigator.performListing の結合経路（絞り込み ON）は適用時に `gitStatusGeneration` を自前でバンプしてから `applyGitStatus` を呼ぶため（SidebarNavigator.swift:225-226）、世代ガードが結合結果を拒否できず、ナビゲーション時に取得した古いスナップショットが無条件に勝つ。

再現シナリオ: 絞り込み ON・大きめのリポジトリでフォルダーへ移動し、結合 gitTask の実行中に外部で `git add .` する。.git/index 監視が単発 refresh を発火して新しいステータス（世代 N+1）を適用した後、結合タスクが完了して世代を N+2 にバンプし古いスナップショットで上書きする。逆順（単発が後着）の場合も、単発側の世代 N+1 が N+2 と一致せず新しい結果が黙って破棄される。いずれも「最後に取得した git 状態が勝つ」という不変条件が破れる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 結合経路の適用が、それより後に開始された単発 refresh（index 監視・保存・トグル起点）の結果を上書き・破棄しない
- [x] #2 「結合適用中に外部で git 状態が変わる」順序を固定した回帰テストがあり、修正を戻すと失敗する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 世代ガードを「最新世代と一致」から「適用済み世代より新しい」(単調増加)へ変える: appliedGitStatusGeneration を追加し、applyGitStatus は generation > appliedGitStatusGeneration のときだけ反映して applied を更新する。
2. performListing の結合経路の gitStatusGeneration 強制バンプを削除し、発行時に取った gitGeneration をそのまま渡す。後発の単発 refresh(世代がより大きい)が勝ち、既に適用済みなら結合結果は落ちる(どちらも同じディレクトリのより新しい状態なので絞り込みは成立する)。
3. cancelPendingListing は gitStatusGeneration をバンプしたうえで applied をそこへ揃え、進行中の全結果を無効化する。
4. 回帰テストを SidebarNavigatorListingCoherenceTests に追加: (a) 結合待ち合わせ中に単発 refresh が新しい状態を先に適用したら、後着の結合結果が上書きしない (b) 結合適用より後に着地した単発 refresh の結果が破棄されない。修正を戻すと落ちることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
世代ガードを「最新世代と一致」から「反映済み世代より新しい」(単調増加)へ変更。appliedGitStatusGeneration を追加し、performListing の結合経路の強制バンプを削除。cancelPendingListing は applied を発行済み世代へ揃えて進行中の取得を一括無効化する。
検証: SidebarNavigatorListingCoherenceTests に 2 件追加(先着の新しい状態を上書きしない / 後着の新しい状態を破棄しない)。修正前は両方とも ["changed.md"] を返して失敗し、修正後に通ることを実行して確認済み。swift test 全体 1094 tests / 161 suites パス。swiftlint は SidebarNavigator.swift の既存 2 件(file_length・opening_brace)のみで main とのベースライン差分ゼロ。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
結合適用(絞り込み ON のフォルダー移動)が gitStatusGeneration を自前でバンプして世代ガードを無効化していたのをやめ、判定を appliedGitStatusGeneration との「より新しいか」比較に統一した。これにより結合結果は「まだ何も反映されていなければ通る」(TASK-294 の要件)を満たしつつ、後から始まった単発 refresh の結果を上書き・破棄しなくなり「最後に開始した取得が勝つ」不変条件が回復する。順序を固定した回帰テスト 2 件で修正前の失敗・修正後の成功を実測。
<!-- SECTION:FINAL_SUMMARY:END -->
