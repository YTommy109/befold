---
id: TASK-264
title: サイドバーで Git 変更のあったファイルのみを表示するフィルターを追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-03 11:25'
updated_date: '2026-08-04 06:17'
labels: []
dependencies:
  - TASK-186
  - TASK-263
documentation:
  - docs/superpowers/specs/2026-07-28-sidebar-git-status-design.md
priority: medium
type: feature
ordinal: 456000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Git リポジトリ内で作業中に「今のブランチで触ったファイル」だけをサイドバーに絞り込めるようにする。ON にすると Git バッジが付くファイル（staged / unstaged / untracked / ブランチ内コミット済み変更のいずれか）だけが一覧に残る。

方針（ユーザー確認済み・2026-08-03）:
- 対象範囲はバッジが付く全て（4 種すべて）。種類別の切り替えは行わない。
- 操作方式は不可視ファイル表示トグルと同型（メニュー項目＋ショートカット＋UserDefaults 永続化＋全ウィンドウ連動）。HiddenFilesPreference と同じ作りに揃える。

前提となる事実（調査済み・2026-08-03）:
- 絞り込みは FileListModel.visibleEntries（既存の filterText / WildcardMatcher による算出プロパティ）に条件を足す形で乗せられる。バッジの真実の源は FileListModel.gitStatuses（キーは FileListEntry.pathKey）。
- 既存の filterText フィルターとは独立に併用できる必要がある（AND 条件）。
- フォルダー行の扱いは TASK-263 の集約結果に依存する（配下に変更を持つフォルダーは残す必要がある）ため、TASK-263 の後に着手する。
- 露出は ViewerWindowController.makeSidebarGitStatusLoader の FeatureGate 分岐でバッジ取得ごと止まるが、トグル UI 自体は別経路なので FeatureGate による非表示化を明示的に入れる必要がある（解除は TASK-187）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 トグル ON で、Git バッジが付くファイル（staged/unstaged/untracked/ブランチ内変更）のみがサイドバーに表示される
- [x] #2 トグル ON でも、配下に変更を持つフォルダー行と親移動行は表示され、フォルダーを辿って目的のファイルへ到達できる
- [x] #3 既存の filterText による絞り込みと併用でき、両方の条件を満たすエントリだけが残る
- [x] #4 トグル状態は UserDefaults に永続化され、全ウィンドウで連動する（不可視ファイルトグルと同じ挙動）
- [x] #5 非 Git ディレクトリ・status 取得失敗時はトグル ON でも一覧が空にならず、フィルター無効として縮退する
- [x] #6 トグル UI は FeatureGate.inProgressFeaturesEnabled が false のとき露出しない
- [x] #7 visibleEntries の絞り込みロジックが単体テストされる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 単純化の検討結果: 新しい Preference クラスを追加すると ViewerWindowManager / ViewerWindowController / SidebarNavigator / AppDelegate すべてに 2 個目の注入引数が増える。代わりに既存 HiddenFilesPreference を SidebarDisplayPreference へ改名し、showChangedFilesOnly を同居させる(注入経路は 1 本のまま・新規配線ゼロ)。
2. SidebarDisplayPreference: showChangedFilesOnly を UserDefaults キー ShowChangedFilesOnly で永続化。
3. FileListModel: 表示用ミラー showChangedFilesOnly を追加し、visibleEntries を filterText と AND で絞る。git 状態が空(非 git / 取得失敗 / 機能無効)なら無効として縮退。.parentNavigation は常に残し、フォルダーは gitFolderStatuses で判定。
4. SidebarNavigator: syncShowHiddenFiles を syncDisplayPreferences へ広げ、両ミラーを同期する。
5. ViewerWindowManager.toggleChangedFilesOnly() + refreshAllSidebars()。AppDelegate に @objc アクションと validateMenuItem のチェックマーク。
6. MainMenuBuilder: FeatureGate.inProgressFeaturesEnabled が false のときは項目自体を追加しない。ショートカットは ⌘⌃G。
7. テスト: FileListModelFilterTests に絞り込み(AND / 縮退 / フォルダー / 親移動)を追加、SidebarDisplayPreference の永続化テストを追加。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: HiddenFilesPreference を SidebarDisplayPreference へ改名し showChangedFilesOnly を同居させた(新しい Preference を足すと 4 クラスへ 2 本目の注入が増えるため、既存の注入経路 1 本を再利用する単純化)。絞り込みは FileListModel.visibleEntries に filterText と AND で乗せ、ファイルは gitStatuses・フォルダーは gitFolderStatuses で判定。git 状態が空/clean のみのときはフィルター無効へ縮退。露出は MainMenuBuilder の FeatureGate 分岐 1 箇所(⌘⌃G、状態はチェックマーク)。

検証: swift test 1059 passed。新規テストは FileListModelFilterTests(7 ケース: 単独/AND/フォルダー/親移動/縮退 2 種/OFF)、SidebarDisplayPreferenceTests(永続化 3 ケース)、MainMenuBuilderTests(FeatureGate と項目有無の一致)、ViewerWindowManagerIntegrationTests(トグルが全ウィンドウへ伝播)、GitStatusReaderIntegrationTests(実 git リポジトリで changed.md と nested のみ残る / 非 git では空にならない)。絞り込みを無効化する変異を入れて新規 3 ケースが落ちることを確認済み(逆向き検証)。swiftformat 0 件、swiftlint は main とルール差分ゼロ(既存の長さ違反の行数が増えたのみ)、xcodebuild build -scheme befold 成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーに「変更されたファイルのみ表示」(⌘⌃G / View メニュー / UserDefaults 永続化 / 全ウィンドウ連動)を追加した。絞り込みは FileListModel.visibleEntries の算出側だけで行い、既存のファイル名フィルターと AND で併用でき、非 git・status 取得失敗時はフィルター無効へ縮退する。露出は FeatureGate.inProgressFeaturesEnabled 配下。単体テスト・実 git リポジトリを使う統合テスト(swift test 1059 passed)と、修正を戻して落ちることの確認で検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
