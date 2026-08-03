---
id: TASK-264
title: サイドバーで Git 変更のあったファイルのみを表示するフィルターを追加する
status: To Do
assignee: []
created_date: '2026-08-03 11:25'
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
- [ ] #1 トグル ON で、Git バッジが付くファイル（staged/unstaged/untracked/ブランチ内変更）のみがサイドバーに表示される
- [ ] #2 トグル ON でも、配下に変更を持つフォルダー行と親移動行は表示され、フォルダーを辿って目的のファイルへ到達できる
- [ ] #3 既存の filterText による絞り込みと併用でき、両方の条件を満たすエントリだけが残る
- [ ] #4 トグル状態は UserDefaults に永続化され、全ウィンドウで連動する（不可視ファイルトグルと同じ挙動）
- [ ] #5 非 Git ディレクトリ・status 取得失敗時はトグル ON でも一覧が空にならず、フィルター無効として縮退する
- [ ] #6 トグル UI は FeatureGate.inProgressFeaturesEnabled が false のとき露出しない
- [ ] #7 visibleEntries の絞り込みロジックが単体テストされる
<!-- AC:END -->
