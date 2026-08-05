---
id: TASK-294
title: 一覧と git ステータスの同時反映が世代ガードで破棄される
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 14:46'
updated_date: '2026-08-04 15:09'
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
- [x] #1 結合タスクの git ステータスが、単発 refreshGitStatuses と競合しても取りこぼされない
- [x] #2 新しいディレクトリの entries が古いディレクトリの gitStatus と組み合わさらない
- [x] #3 .git/index 更新とフォルダー移動が同時に起きても絞り込みが一瞬外れないことをテストで再現・検証する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: FileListModel 側は既に entriesDirectory との突き合わせ + pendingGitStatus で一覧と状態の整合を担保しており、AC#2 はモデル層で成立済み。残る穴は SidebarNavigator の gitStatusGeneration ガードだけなので、世代を 1 本化せずガードの扱いだけを直す。
2. performListing の結合タスクは、開始時に捕まえた gitGeneration ではなく、反映直前に gitStatusGeneration を採り直して適用する(listingGeneration のガードを通った時点でこれが最新の一覧なので、その対の状態は常に反映されるべき)。併走していた単発 refreshGitStatuses は世代が古くなるので無効化される。
3. 回帰テストを SidebarNavigatorListingCoherenceTests に追加し、修正を戻すと落ちることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
修正: BefoldApp/befold/App/SidebarNavigator.swift の performListing で、開始時に捕まえた gitGeneration を使うのをやめ、反映直前に gitStatusGeneration を採り直して applyGitStatus に渡す。listingGeneration のガードを通った時点で最新の一覧なので、その対で取った git 状態は常に反映される。逆に併走していた単発 refreshGitStatuses は世代が古くなり無効化される(連続移動時の古い結果は listingGeneration のガードが先に弾くため、既存の discardsStaleStatuses は変わらず通る)。

検証: 追加した回帰テスト『移動中に .git/index 由来の取得が割り込んでも一覧と対の git 状態を捨てない』(SidebarNavigatorListingCoherenceTests)。修正前のコード(gitGeneration を捕まえる形)へ戻すと visibleEntries に clean.md が混ざって失敗し、修正後は通ることを実測。swift test 全体 1081 tests / 161 suites 通過。

swiftlint: 変更ファイルの警告は file_length と opening_brace の 2 件で、いずれも main 時点から存在するもの(opening_brace は行番号のみ変化)。file_length は行数が 402→404 に増えたぶん数値表記だけ変わる。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
performListing が一覧と対で取った git ステータスを、待ち合わせ中に走った単発 refreshGitStatuses に世代を進められて捨てていた問題を修正。反映直前に gitStatusGeneration を採り直すことで、対の結果は必ず反映され、併走していた単発取得のほうが無効化されるようにした。回帰テストを追加し、修正を戻すと絞り込みが外れて落ちることを実測で確認、swift test 全体(1081 tests)も通過。
<!-- SECTION:FINAL_SUMMARY:END -->
