---
id: TASK-300
title: ウィンドウクローズ後も絞り込み OFF の git 適用が .git/index 監視を再アームする
status: To Do
assignee: []
created_date: '2026-08-04 16:35'
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
- [ ] #1 ウィンドウクローズ（cancelPendingListing）後、実行中だった git 取得の完了が applyGitStatus・監視の再アームのいずれも引き起こさない
- [ ] #2 クローズ後に .git/index 監視が生き残らないことを検証する回帰テストがあり、修正を戻すと失敗する
<!-- AC:END -->
