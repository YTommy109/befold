---
id: TASK-300
title: ウィンドウクローズ後も絞り込み OFF の git 適用が .git/index 監視を再アームする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 16:35'
updated_date: '2026-08-04 16:45'
labels:
  - git-filter
  - review-finding
dependencies: []
priority: high
type: bug
ordinal: 110000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の CONFIRMED 指摘。TASK-297 で追加した絞り込み OFF 用の分離適用タスク（SidebarNavigator.swift:234-237）には host／listing 世代のガードがなく、Task のキャンセルも協調的にしか効かない。

再現シナリオ: 絞り込み OFF で git フォルダーへ移動し（git status サブプロセス起動）、直後にウィンドウを閉じる。cancelPendingListing() が pendingGitStatusTask をキャンセルし gitIndexWatch.stop() を呼ぶが、実行中の loadGitStatuses はキャンセルを観測せず実結果を返す。キャンセル後に gitStatusGeneration をバンプする処理がないため applyGitStatus のガードを通過し、gitIndexWatch.update(indexURL:) が閉じたウィンドウのために .git/index の DispatchSource 監視を再生成する。以後そのリポジトリで git 操作があるたびに、存在しないウィンドウのために refreshGitStatuses が発火して git サブプロセスが起動し続ける（navigator が生きている限り）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ウィンドウクローズ（cancelPendingListing）後、実行中だった git 取得の完了が applyGitStatus・監視の再アームのいずれも引き起こさない
- [x] #2 クローズ後に .git/index 監視が生き残らないことを検証する回帰テストがあり、修正を戻すと失敗する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. cancelPendingListing が世代を進めていない点を突く回帰テストを追加(絞り込み OFF・git 取得をゲートで保留 → close → 完了させ、監視が張られないことを確認)
2. cancelPendingListing で listing/gitStatus/baseDirectory の世代をまとめて進め、遅れて着地する結果を全経路で捨てる
3. swift test で回帰確認、修正を戻して失敗することも確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
cancelPendingListing で listing/gitStatus/baseDirectory の 3 世代をまとめて進める形にした(applyGitStatus 側にガードを足すのではなく、キャンセル点で全経路の遅着結果を一括で無効化する)。回帰テスト cancelPendingListingPreventsWatcherRearm を追加し、修正前は watchers が非空で失敗、修正後は全 1010 テストが通ることを確認済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
cancelPendingListing で 3 つの世代番号を進め、閉じた後に着地する git 結果が applyGitStatus と .git/index 監視の再アームを起こさないようにした。回帰テストで修正前失敗・修正後成功を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
