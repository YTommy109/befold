---
id: TASK-442.5
title: 履歴を独立型へ出し、選択記憶をフォルダ移動へ吸収してベースラインを締め直す
status: Done
assignee: []
created_date: '2026-08-11 07:36'
updated_date: '2026-08-11 12:17'
labels: []
dependencies:
  - TASK-442.4
parent_task_id: TASK-442
ordinal: 677000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-442 の仕上げ。ここまでで型グループは 420〜430 行の見込みで、AC の 400 行にはまだ届かない。

1. SidebarNavigator+History.swift (70 行) を独立型へ出す。この extension は 4 本の中で唯一 doc が「行数のため」ではなく「一覧・git 状態の取得とは独立した関心事」と書いており (+History.swift:5)、触る本体 stored は history (専有) / fileListModel / host の 3 個だけ。着手判断のライン: applyHistoryEntry が refreshFileList(applyCustomSelection:) を呼び返すため逆方向の参照が 1 本要る。これがクロージャ 1 個または weak 参照 1 本で済むなら実施し、3 本以上必要になるなら実施せず理由を記録する。
2. SidebarNavigator+SelectionMemory.swift (23 行) を +FolderNavigation.swift へ吸収する。メソッド 2 個・stored 1 個で、呼び出し元は navigateToFolder の 2 箇所のみ。責務が分かれている証拠にならないファイル分割であり、同一ファイルにすれば selectionMemory を private へ落とせる。
3. e94161d で緩んだ隠蔽の始末。folderEntryURL(forKey:) は TASK-442.2 で FileListModel へ移って本体から消えている。host は +FolderNavigation / +History が読むため Swift の private (ファイルスコープ) では戻せない。private(set) のまま残す理由を doc コメントに明記する。
4. scripts/type-group-baseline.txt から SidebarNavigator のエントリを消す (--update-baseline)。新型が閾値未満であることも確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 型グループの合算行数が 400 行以下になっている (scripts/check-type-group-size.sh --check が通る)
- [x] #2 scripts/type-group-baseline.txt から SidebarNavigator のエントリが消えている
- [x] #3 SidebarNavigator+SelectionMemory.swift が無くなり、selectionMemory が private になっている
- [x] #4 履歴を独立型へ出したか、出さなかった場合はその理由 (逆方向の参照が何本必要だったか) が Implementation Notes に記録されている
- [x] #5 host が private(set) のまま残る理由が doc コメントに明記されている
- [x] #6 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実施内容と実測

型グループ 493 → **360 行**。AC#1 (400 行以下) を満たし、ベースラインから SidebarNavigator のエントリが消えた (--check が通る)。

### 履歴の切り出しは実施した (AC#4)

着手判断ラインは「applyHistoryEntry が refreshFileList を呼び返すための逆参照が 1 本で済むか」だった。**実測 1 本**(weak navigator)で済んだため実施した。SidebarHistoryController (95 行) は fileListModel / host / navigator(weak) の 3 つだけを持ち、navigator への逆参照の用途は refreshFileList(applyCustomSelection:) 1 箇所のみ。その旨を型の doc に記録した。

### 選択記憶は本体へ吸収した (AC#3)

当初の計画は +FolderNavigation.swift への吸収だったが、それでは AC#3 (selectionMemory を private) を満たせない。Swift の private はファイルスコープで、stored property は extension に置けないため、**触るコードが SidebarNavigator.swift 側に無ければ private にできない**。2 つのヘルパーを本体へ移し、selectionMemory を private にした。ヘルパー自体は navigateToFolder (別ファイル) から呼ぶため internal のまま。

### AC#1 に 44 行届かず、一覧取得のパイプラインも切り出した (スコープ追加)

タスク記載の 4 項目をすべて実施した時点で 444 行で、AC#1 に 44 行届かなかった (タスク自身も「420〜430 行の見込みで届かない」と予告していた)。ユーザー判断で「一覧取得のパイプラインをもう 1 型切り出す」を選択し、SidebarListingCoordinator (166 行) を新設した。

directoryLister / 世代 / pendingTask / refreshFileList / performListing / syncDisplayPreferences を持つ。syncDisplayPreferences を同居させたのは、隠しファイル・並び順・絞り込み・レイアウトが**列挙の入力**だから。TASK-293/294/297/298 の不変条件はそのまま移し、絞り込み ON/OFF の分岐も変えていない。

### 作業中に作り込んだ不具合 1 件 (自己検出)

listing を切り出した際、attach(to:) で listing.attach(to:) を呼び忘れ、host が nil のままになって refreshFileList が全く動かなくなった。SidebarNavigatorGitStatusTests の「取得結果の .git/index を監視し、その変更で状態を取り直す」が落ちて検出できた (watchers/policies が空)。attach の 1 行追加で解消。

## 検証結果

- swift test: 1297 tests / 182 suites すべて成功。テストの変更は不要だった
- swiftlint: ブランチ HEAD 比で**真の新規 0 件 / 解消 1 件**。解消したのは SidebarNavigator+History.swift の opening_brace で、移設先で多行条件を Optional.flatMap による 1 行の束縛へ書き換えたため (CLAUDE.md の「多行にまたがる if / guard は避ける」に沿う)
- scripts/check-type-group-size.sh --check: ベースライン以内
- xcodegen generate 実行済み

## 分割後の SidebarNavigator (360 行)

残る stored は fileListModel / selectionMemory / host / 協力型 5 つ。自身が持つ処理は選択同期 (syncAfterSwitch / restoreSelection)、選択記憶の 2 ヘルパー、フォルダ移動 (+FolderNavigation)、協力型への薄い委譲。FileListModel を書く型が 5 つになったが、属性は重ならない (行 = tree / baseDirectory = resolver / git 状態 = coordinator / 履歴 = historyController / 選択・カレントディレクトリ = navigator)。各型の doc にこの分割表を記載した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
履歴を SidebarHistoryController (95 行) へ、一覧取得のパイプラインを SidebarListingCoordinator (166 行) へ切り出し、選択記憶の 2 ヘルパーを本体へ吸収して selectionMemory を private にした。履歴の切り出しは着手判断ラインどおり逆参照 1 本 (weak navigator / 用途は refreshFileList 1 箇所) で済んだ。一覧パイプラインの切り出しはタスク記載の 4 項目だけでは AC#1 に 44 行届かなかったためユーザー判断で追加したもの。型グループ 493 → 360 行で、ベースラインから SidebarNavigator のエントリが消え --check が通る。host は別ファイルの extension が読むため private へ戻せず、private(set) で書き込みを attach(to:) に限定している旨を doc に明記した。swift test 1297 件成功、swiftlint はブランチ HEAD 比で新規 0 件・解消 1 件。
<!-- SECTION:FINAL_SUMMARY:END -->
