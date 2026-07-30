---
id: TASK-190
title: 「最近使ったリポジトリを開く」メニューを追加する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 14:35'
updated_date: '2026-07-30 23:25'
labels: []
dependencies: []
ordinal: 264000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
開いたファイルが git リポジトリ内だった場合、そのリポジトリ（本体または worktree）のルートを自動的に「最近使ったリポジトリ」として記憶し、メニューから素早く再オープンできるようにする。

## 開く挙動（確定）
メニュー項目を選ぶと、そのリポジトリ/worktree の**最後のタブ構成（開いていたファイル・選択タブ）が記憶されていればそれを復元し、新規ウィンドウとして開く**。記憶が無ければ、従来どおりルートディレクトリを新規ウィンドウのサイドバーで開く（既存の「フォルダを開く」経路に乗せる）。前回のグローバルセッション復元（SessionRestorer によるアプリ全体の起動時復元）自体の仕様変更は本タスクのスコープ外。今回追加するのはリポジトリ単位の別枠の記憶であり、既存のアプリ全体セッション復元とは独立に動作する。

## 記憶する単位
開いたファイルから解決した git リポジトリのルート（worktree の場合は worktree のルート）。重複排除キーはルートパス。最終利用順で並べ、保持件数上限（10件）を設ける。加えて、そのリポジトリに属するウィンドウが閉じるたびに、そのウィンドウのタブ構成（TabGroup: paths + selectedPath）を最新状態として記憶する。同一リポジトリを複数ウィンドウで同時に開いていた場合は最後に閉じたウィンドウの状態のみ残る（レアケースとして許容）。永続化は UserDefaults。

## 本体 vs worktree の区別
git rev-parse の --git-common-dir と --git-dir の比較（一致＝本体、不一致＝worktree）等で判定し、一覧上で本体か worktree かを区別できるラベル/表示にする（worktree はディレクトリ名を併記、例: befold (olla-rattler)。本体は接尾辞なし）。

## メニュー配置
File メニュー内に「Open Recent」「Bookmarks」と並ぶ独立したサブメニュー「Recent Repositories」を新設する。保持件数上限は10件、末尾に「Clear Menu」項目を用意する。存在しなくなった worktree 等はメニュー表示直前（menuNeedsUpdate）に毎回チェックして一覧から除去する。

設計の詳細は docs/superpowers/specs/2026-07-30-recent-repositories-menu-design.md を参照。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 git リポジトリ内のファイルを開くと、そのリポジトリ/worktree のルートが最近使ったリポジトリとして自動記憶される
- [x] #2 メニューから項目を選ぶと、記憶されたタブ構成があればそれを復元して新規ウィンドウで開く。無ければそのルートディレクトリを新規ウィンドウのサイドバーで開く
- [x] #3 一覧で本体リポジトリと worktree を区別できる
- [x] #4 同一ルートは重複せず、最終利用順に並び、保持件数上限を超えた古いものは落ちる
- [x] #5 非 git のファイルを開いても一覧に追加されない
- [x] #6 一覧・タブ構成の記憶はアプリ再起動をまたいで永続化される
- [x] #7 リポジトリのウィンドウが閉じるたびに、そのリポジトリの最後のタブ構成（開いていたファイルと選択タブ）が更新記憶される
- [x] #8 記憶したタブ構成のファイルが一部/全部存在しない場合は、存在するものだけに絞って復元するか、全て無ければルートフォルダを開くフォールバックへ縮退する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
docs/superpowers/plans/2026-07-30-recent-repositories-menu.md の 8 タスク構成の実装計画に従う(Task1: GitRepository.repositoryLabel / Task2: RecentRepositoriesStore / Task3: MenuController+l10n / Task4: MainMenuBuilder / Task5: ViewerWindowController.repositoryRoot / Task6: ViewerWindowManager 記録配線 / Task7: SessionRestorer.openRepository / Task8: AppDelegate 配線)。subagent-driven-development で実行する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了(コミット b28340dd..73b6259c、全14コミット)。検証: swift test フルスイート 904/904 PASS。AC対応の証跡: #1/#5 ViewerWindowManagerRecentRepositoriesTests、#2/#8 SessionRestorerTests(openRepository系5件)、#3 GitRepositoryTests(実git worktreeでのラベル検証)、#4/#6 RecentRepositoriesStoreTests、#7 closingTabsOneByOneKeepsFullTabGroup ほか。
設計判断の変更(最終レビュー起点・ユーザー承認済み): (1) フォールバックはルートを DirectoryLister.resolveFileToOpen で中のファイルへ解決してから開く (2) タブ構成記録は didBecomeKey+close の縮小拒否書き込み+applicationShouldTerminate での強制スナップショット(windowWillClose 時は tabGroup が既に nil になる AppKit 実挙動のため) (3) git 呼び出し(root+ラベル解決)は Task.detached で非同期化 (4) pruneMissing はデコード不能データを温存。design doc も更新済み。
残: 計画 Task 8 Step 4 の手動スモークテスト(GUI 目視確認)が未実施 — これが完了すれば Done にできる。

手動スモークテスト実施済み(ユーザー確認)。併せて File メニューの並びを見直し、「開くコマンド(Open…/Quick Open)」と「記憶済みリスト(Open Recent/Recent Repositories/Bookmarks)」を区切り線で分け、履歴2つを隣接させた(commit 2f7ec778)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
git リポジトリ内のファイルを開くとリポジトリ/worktree ルートを自動記憶し、File > Recent Repositories から最後のタブ構成ごと復元できるようにした(記憶が無ければルート内のファイルをサイドバー表示で開く)。RecentRepositoriesStore(UserDefaults永続化・上限10件・最終利用順)と RecentRepositoriesMenuController を RecentDocuments 系と同型で新設し、GitRepository に --git-common-dir/--git-dir 比較による worktree ラベル解決を追加。タブ構成は didBecomeKey/close の縮小拒否書き込みと終了時の強制スナップショットで保持する(windowWillClose 時点では tabGroup が既に nil になる AppKit 挙動への対応)。git 呼び出しは Task.detached でメインスレッド外へ。検証: swift test 904/904 PASS + 手動スモークテスト。
<!-- SECTION:FINAL_SUMMARY:END -->
