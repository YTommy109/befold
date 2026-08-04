---
id: TASK-297
title: フォルダー移動が毎回 git status の完了を待つようになっている
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 14:47'
updated_date: '2026-08-04 16:09'
labels:
  - git-filter
  - review-finding
  - performance
dependencies:
  - TASK-294
priority: medium
type: bug
ordinal: 495000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
/code-review (high) の検証済み指摘（CONFIRMED）。

performListing が onApplied の前に `await gitTask.value` を挟むため、ディレクトリ列挙が終わっても git サブプロセスが返るまで entries が反映されない。git status は絞り込みの ON/OFF に関係なく .always で取得されるため、絞り込みを使っていないユーザーもフォルダー移動・ウィンドウフォーカス復帰（refreshFileList）・ソート変更のたびに待たされる。大きい/コールドなリポジトリでは 1〜2 秒前のディレクトリの内容が表示されたままになる。

該当: BefoldApp/befold/App/SidebarNavigator.swift:214

注: TASK-294 と同じ経路を触るため、対応方針は合わせて検討すること（同時反映を保ちつつ待ち時間を消す設計が要る）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 絞り込み OFF のときフォルダー移動が git status の完了を待たない
- [ ] #2 絞り込み ON でも、一覧と git ステータスの整合（TASK-294）を崩さずに体感レイテンシを改善する
- [x] #3 レイテンシは固定間隔の負荷合計ではなく、移動から反映までの実測で評価する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化検討: 一覧と git を揃える必要があるのは絞り込み(showChangedFilesOnly)が ON のときだけ。OFF では絞り込まないので縮退しようがなく、git 状態はバッジにしか効かない。新しい状態を足さず、待つ条件を ON に限定するだけで済む。
2. performListing で couplesGitStatus = fileListModel.showChangedFilesOnly を捕まえ、OFF なら列挙が終わり次第 onApplied を呼ぶ。git 状態は単発 refreshGitStatuses と同じ世代ガードで遅れて反映する(FileListModel の pendingGitStatus が一覧と突き合わせるため先着後着どちらでも整合は崩れない)。
3. 重複した withTaskCancellationHandler は awaitingCancellable ヘルパーへ集約する。
4. 回帰テストを SidebarNavigatorListingCoherenceTests へ追加し、修正前に落ちることを確認する。
5. レイテンシは移動→一覧反映の実測(実 git subprocess)で評価する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
修正: BefoldApp/befold/App/SidebarNavigator.swift の performListing。開始時に showChangedFilesOnly を捕まえ(couplesGitStatus)、OFF なら列挙が終わり次第 onApplied を呼んで一覧を反映する。git 状態は一覧と切り離した反映タスク(pendingGitStatusTask)から、単発 refreshGitStatuses と同じ世代ガードで遅れて反映する。ON のときは TASK-293/294 の結合経路をそのまま維持する。重複していた withTaskCancellationHandler は awaitingCancellable ヘルパーへ集約した。

実測(AC#3): 移動→一覧反映までの経過時間を、実 git subprocess(GitStatusStore + GitStatusReader)と実 DirectoryLister を使った使い捨てテストで計測。対象は 1287 ファイルの実リポジトリ(~/develop/interest/trpc)、各 5 回・毎回 store を作り直してキャッシュ無しの状態から測定。
- 修正後 OFF: 1, 1, 1, 2, 8 ms
- 修正後 ON : 248, 313, 320, 394, 428 ms
- 修正前(couplesGitStatus = true に固定して再現)OFF: 185, 255, 311, 320, 323 ms
つまり絞り込み OFF のフォルダー移動は約 300ms → 約 1ms になった。参考として rev-parse + status の subprocess 自体は同リポジトリで約 65ms、この worktree では約 10-20ms。TASK-297 の Description にある「1〜2 秒」は暖まったリポジトリでは再現しない(見積もりであって実測ではなかった)。

回帰テスト: 『絞り込み OFF のフォルダー移動は git 状態の完了を待たずに一覧を反映する』(SidebarNavigatorListingCoherenceTests)。修正前は pendingListingTask 完了時点で既に gitStatus が入っており落ちることを実測。TASK-293/294 の既存 2 テスト(いずれも絞り込み ON)は変更なく通る。

AC#2 は未達: ON 側のレイテンシは約 320ms のままで改善していない。ON では絞り込みの結論そのものが git 状態に依存するため、待ちを消すには『git が届くまで一覧を空(または読み込み中)で見せる』という UX の変更が要る。全件を一瞬見せる TASK-293 の再発を避けたまま体感を良くする案として別途判断が必要。

swiftlint: 変更後の SidebarNavigator.swift は file_length と opening_brace の 2 件のみで main と同じ。作業途中で type_body_length(251/250)が新規発生したため、Navigation History 節を同ファイル内の extension へ切り出して解消した(責務としても一覧・git 取得とは独立)。swiftformat は差分なし。swift test 全体 1089 tests / 161 suites 通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
performListing が絞り込みの ON/OFF に関わらず git 状態の完了を待ってから一覧を反映していた問題を修正。揃える必要があるのは絞り込み ON のときだけなので、待つ条件を ON に限定し、OFF では列挙が終わり次第一覧を反映して git 状態は単発取得と同じ世代ガードで遅れて反映するようにした。実 git subprocess を使った移動→反映の実測で、OFF は約 300ms → 約 1ms、ON は結合経路のまま従来どおり(約 320ms)。回帰テストを追加し修正前に落ちることを実測、swift test 全体 1089 tests 通過。AC#2(ON 側のレイテンシ改善)は未達で、実現には『git が届くまで一覧を空で見せる』という UX 判断が要るため別途起票・相談が必要。
<!-- SECTION:FINAL_SUMMARY:END -->
