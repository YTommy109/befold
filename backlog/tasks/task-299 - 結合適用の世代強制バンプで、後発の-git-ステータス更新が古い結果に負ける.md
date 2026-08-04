---
id: TASK-299
title: 結合適用の世代強制バンプで、後発の git ステータス更新が古い結果に負ける
status: To Do
assignee: []
created_date: '2026-08-04 16:34'
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
- [ ] #1 結合経路の適用が、それより後に開始された単発 refresh（index 監視・保存・トグル起点）の結果を上書き・破棄しない
- [ ] #2 「結合適用中に外部で git 状態が変わる」順序を固定した回帰テストがあり、修正を戻すと失敗する
<!-- AC:END -->
