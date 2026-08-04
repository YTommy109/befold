---
id: TASK-294
title: 一覧と git ステータスの同時反映が世代ガードで破棄される
status: To Do
assignee: []
created_date: '2026-08-04 14:46'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: high
type: bug
ordinal: 492000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の検証済み指摘。TASK-293 で導入した「一覧と git ステータスを揃えて反映する」経路に穴がある。

performListing は開始時に gitStatusGeneration を捕捉するが、実行中に GitIndexWatch の発火や onContentReloaded 由来の単発 refreshGitStatuses が走ると gitStatusGeneration が進む。結合タスクが先に完了しても applyGitStatus の `guard generation == gitStatusGeneration` に弾かれ、正しい git ステータスが捨てられる。一方 entries は listingGeneration のガードしか見ないためそのまま反映され、新しいディレクトリの entries と古いディレクトリの gitStatus が組み合わさる。

結果 activeGitChangeFilter が nil になり、単発 fetch が返るまで絞り込みの外れた全ファイル一覧が表示される（TASK-293 が消したはずのチラつきの再発）。

該当: BefoldApp/befold/App/SidebarNavigator.swift:220, :232
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 結合タスクの git ステータスが、単発 refreshGitStatuses と競合しても取りこぼされない
- [ ] #2 新しいディレクトリの entries が古いディレクトリの gitStatus と組み合わさらない
- [ ] #3 .git/index 更新とフォルダー移動が同時に起きても絞り込みが一瞬外れないことをテストで再現・検証する
<!-- AC:END -->
