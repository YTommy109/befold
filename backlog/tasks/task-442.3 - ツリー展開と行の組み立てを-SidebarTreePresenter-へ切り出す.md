---
id: TASK-442.3
title: ツリー展開と行の組み立てを SidebarTreePresenter へ切り出す
status: Done
assignee:
  - '@claude'
created_date: '2026-08-11 07:35'
updated_date: '2026-08-11 11:28'
labels: []
dependencies:
  - TASK-442.1
parent_task_id: TASK-442
ordinal: 675000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
SidebarNavigator+Expansion.swift (87 行) 全体と、SidebarNavigator の expansion / childrenLister を新規の @MainActor final class SidebarTreePresenter へ移す。展開状態 (SidebarExpansion) / 行の組み立て (applyRows) / 子リストの取得 (childrenLister) は別々の関心が同居しているのではなく、1 つの出力 (FileListModel.entries) を作るための状態・材料・生成器であり、SidebarExpansion.swift:14-19 の doc が「展開状態と行生成を切り離すな」と指示している内容を型境界として実体化する。

責務分離であって行数回避でないことの実証として、次の 2 つを同じタスクで行う。

1. presenter が rootRows を stored property として保持し、rebuildRows() の fileListModel.entries.filter { $0.depth == 0 } による逆算 (+Expansion.swift:47) を消す。
2. SidebarExpansion.ExpansionToken に URL を持たせ、reloadExpandedChildren が folderEntryURL でフォルダ URL を引き直している (+Expansion.swift:73) のをやめる。beginExpanding の呼び出し元 expandFolder(_:at:) は URL を持っているため、券に載せれば引き当て自体が不要になる。

presenter は注入しない。childrenLister だけを SidebarNavigator.init の引数として受け、内部で生成して渡す (SidebarExpansion の非注入方針 = TASK-319 と同型の事故防止を維持する)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 SidebarNavigator+Expansion.swift が無くなり、内容が SidebarTreePresenter へ移っている
- [x] #2 presenter が lastListing を private stored として保持し、SidebarNavigator から lastListing が消えている（depth == 0 のフィルタによる逆算は 442.1 で解消済み）
- [x] #3 ExpansionToken が URL を持ち、reloadExpandedChildren がフォルダ URL の引き当てを行わない
- [x] #4 presenter は SidebarNavigator.init の引数ではなく内部で生成される（ウィンドウごとに 1 つが構造で守られる）
- [x] #5 tree が private で、外部（ViewerWindowManager / ViewerWindowAssembler）は SidebarNavigator の薄い委譲メソッド経由でのみ展開を操作する
- [x] #6 swift test が既存どおり通り、main との swiftlint 差分に真の新規が無い
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarTreePresenter.swift を新設する（@MainActor final class）。fileListModel と childrenLister を init で受け、expansion を内部で生成する。applyRows / rebuildRows / expandFolder / collapseFolder / reloadExpandedChildren / loadChildren / invalidateAll を移す。lastListing は presenter の private stored にする（現状は SidebarNavigator の internal var）。
2. SidebarExpansion.ExpansionToken に url を持たせる。beginExpanding(_:at:) がフォルダ URL を受けて保持し、invalidateChildren が発行する券にも載せる。collapse / invalidateAll で URL も捨てる。reloadExpandedChildren の folderEntryURL 引き当てを消す。
3. SidebarNavigator から expansion / childrenLister / lastListing / SidebarNavigator+Expansion.swift を削除し、let tree: SidebarTreePresenter を init 内で生成する（注入引数にしない = AC#4）。childrenLister は従来どおり init 引数で受けて presenter へ渡す。
4. 呼び出し元を tree 経由へ差し替える: SidebarNavigator.refreshFileList / performListing / cancelPendingListing、+FolderNavigation.navigateToFolder、ViewerWindowManager.toggleSidebarLayoutMode、ViewerWindowAssembler の onExpandFolder/onCollapseFolder、SidebarNavigatorExpansionTests。
5. SidebarRowAssemblySingleSourceTests の期待ファイル名を SidebarTreePresenter.swift へ更新する。SidebarExpansion.swift の doc（行の反映点の記述）も追随させる。
6. xcodegen generate → swift build → swift test → swiftformat → swiftlint 差分確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 設計レビュー結果 (実装前 / 2026-08-11)

responsibility-reviewer を回した。3 件の論点のうち 2 件を採用、1 件は反対の判断をした。

### 採用: tree は private + 薄い委譲 (H1)

ViewerWindowManager.swift:150 が sidebar.expansion.invalidateAll() で内部状態へ直接到達しており、SidebarNavigator+Expansion.swift:9 の「外から呼んでよいのは expandFolder / collapseFolder だけ」という doc は現時点で既に破れている。tree を internal let で公開すると applyRows / rebuildRows / lastListing 相当まで到達可能になり、破れの面積が広がる。private let tree とし、SidebarNavigator に expandFolder / collapseFolder / discardExpansion の 3 本だけ残す。AC#5 として固定した。

### 採用しない: URL 表を presenter 側へ置く案 (H2)

レビューは SidebarExpansion に [String: URL] を足すのを「第 2 の関心」として避け、presenter の private 表にすることを推奨した。採らない。SidebarExpansion.collapse(key) は key と配下 (hasPrefix(key + "/")) をまとめて捨てる (SidebarExpansion.swift:120)。URL 表を presenter へ置くと、この接頭辞ルールを presenter 側でも複製しないと表が stale になり、同じ不変条件を 2 箇所が持つ形になる。expandedKeys / children / generations と同じ辞書群の 1 本として SidebarExpansion に置けば掃除が既存のループに同居して破れない。AC#3 は原文のまま維持する。

指摘された挙動差 (リネーム・フォルダ消失時、引き当てスキップではなく childrenLister が nil を返して .failed が着地する) は置き場所と独立の論点で、かつ表示には出ない。stale な key はルート再列挙後どの行にも一致せず、material.failed に入っても行を持たないため描画されない。この判断は SidebarExpansionTests のケースで固定する。

### 採用: AC#2 の書き換え (M1)

AC#2 の rootRows / depth == 0 逆算は 442.1 で既に解消済み (+Expansion.swift:40-45 の doc が経緯を記録)。今回移すのは lastListing: DirectoryListing。AC#2 をその形へ書き換えた。

### 実測と見積もり (M2)

型グループ SidebarNavigator = 598 行 (本体 354 / +Expansion 84 / +History 70 / +FolderNavigation 67 / +SelectionMemory 23)。442.3 後は約 500 行、新設 SidebarTreePresenter は独立グループで約 130 行。注入クロージャは 5 個のまま減らない (childrenLister は presenter へ素通しするが init 引数には残る)。親 AC#1 (400 行以下) / AC#4 (クロージャ 3 個以下) は 442.3 単体では満たされず、442.4 / 442.5 で到達する。

### 追随が要る箇所 (L3)

- SidebarRowAssemblySingleSourceTests の期待ファイル名 (SidebarNavigator+Expansion.swift → SidebarTreePresenter.swift)
- SidebarExpansion.swift:16 の doc (行の反映点の型名)
- scripts/type-group-baseline.txt の SidebarNavigator エントリ (ラチェットなので下げる)
- FileListView.swift:15 のコメントは委譲メソッドを残す方針なら文言のまま正しい

### 持ち越す既存の窓 (L2)

reloadExpandedChildren はルート列挙の発行前に呼ばれるため、子リストが先着すると古い lastListing で 1 回組み直される (意図は +Expansion.swift:63-67 に記録済み)。現状と同じ挙動で今回悪化はしないため、presenter の doc にこの窓の存在を残すにとどめる。

## 検証結果 (実装後)

- swift test: 1297 tests / 182 suites すべて成功 (--skip Integration --skip FileWatcherTests)
- swiftlint: HEAD (7a4b851) を git archive で別ディレクトリへ展開して測り、作業ツリーと比較。**真の新規 0 件 / 解消 0 件**。origin/main との比較では BefoldRenderKit に 3 件の新規が出るが、これは TASK-440 の ViewerRenderer 分割によるファイル改名 (ViewerRenderer+DirectHTMLLinkPolicy.swift → DirectHTMLLinkPolicy.swift 等) で既にブランチ上にあるもので、本タスクの変更由来ではない
- 型グループ: SidebarNavigator 598 → **548 行**。新設 SidebarTreePresenter は独立グループで 130 行。事前見積もり (約 500) より 48 行多いのは、tree を private にしたことで薄い委譲 4 本 (expandFolder / collapseFolder / discardExpansion / applyRows) とその doc が本体に残ったため
- scripts/check-type-group-size.sh --update-baseline でベースラインを更新
- xcodegen generate 実行済み (SidebarTreePresenter.swift 追加 / SidebarNavigator+Expansion.swift 削除)

## 設計判断と担保

- applyRows は SidebarNavigator の internal な委譲として残した。SidebarNavigator+FolderNavigation (別ファイルの extension) が呼ぶため、Swift の private (ファイルスコープ) では届かない。presenter そのものは private のままなので、invalidateExpansion / rebuildRows / lastListing はウィンドウ層から到達できない
- ExpansionToken の URL 搭載は SidebarExpansionTests に 2 ケース追加して固定した。invalidateChildrenCarriesOriginalFolderURL (券が開始時の URL を運ぶ = 引き当てが復活したら落ちる) と staleFolderReloadLandsFailedWithoutRows (消えたフォルダは .failed が着地するが material.childrenByPathKey には入らず行を生まない)

## 本タスク外の申し送り

scripts/type-group-baseline.txt の FileListModel エントリが 459 → 487 へ動いた。これは TASK-442.2 で引き当て述語を FileListModel へ移したときの増分がベースラインへ記録されないまま残っていたもので、本タスクの --update-baseline で一緒に取り込まれた。ラチェットは pre-commit の warn-type-group-growth.sh が警告するだけで落とさないため見逃されていた。

## 検証結果 (実装後)

- swift test: 1297 tests / 182 suites すべて成功 (--skip Integration --skip FileWatcherTests)
- swiftlint: ブランチ HEAD (7a4b851) を git archive で別ディレクトリへ展開して測り、作業ツリーと比較。真の新規 0 件 / 解消 0 件。origin/main との比較では BefoldRenderKit に 3 件の新規が出るが、これは TASK-440 の ViewerRenderer 分割によるファイル改名で既にブランチ上にあるもので、本タスクの変更由来ではない
- 型グループ: SidebarNavigator 598 → 548 行。新設 SidebarTreePresenter は独立グループで 130 行。事前見積もり (約 500) より多いのは、tree を private にしたことで薄い委譲 4 本 (expandFolder / collapseFolder / discardExpansion / applyRows) とその doc が本体に残ったため
- scripts/check-type-group-size.sh --update-baseline でベースライン更新、xcodegen generate 実行済み

## 設計判断と担保

- applyRows は SidebarNavigator の internal な委譲として残した。SidebarNavigator+FolderNavigation (別ファイルの extension) が呼ぶため Swift の private (ファイルスコープ) では届かない。presenter 自体は private のままなので invalidateExpansion / rebuildRows / lastListing はウィンドウ層から到達できない
- ExpansionToken の URL 搭載は SidebarExpansionTests へ 2 ケース追加して固定した。invalidateChildrenCarriesOriginalFolderURL (券が開始時の URL を運ぶ = 引き当てが復活したら落ちる) と staleFolderReloadLandsFailedWithoutRows (消えたフォルダは .failed が着地するが行を生まない)

## 本タスク外の申し送り

scripts/type-group-baseline.txt の FileListModel エントリが 459 → 487 へ動いた。TASK-442.2 で引き当て述語を FileListModel へ移した増分がベースラインへ記録されないまま残っていたもので、本タスクの --update-baseline で一緒に取り込まれた。ラチェットは pre-commit の warn-type-group-growth.sh が警告するだけで落とさないため見逃されていた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
SidebarNavigator+Expansion.swift (84 行) と expansion / childrenLister / lastListing を新設の SidebarTreePresenter (130 行) へ移し、fileListModel.entries を作る関心を 1 型へ閉じた。lastListing が private になり「書いてよいのは applyRows だけ」が doc の約束から構造の保証になった。ExpansionToken にフォルダ URL を載せ、reloadExpandedChildren の pathKey からの引き当てを消した。presenter は SidebarNavigator.init 内でのみ生成し private で保持、外部へは expandFolder / collapseFolder / discardExpansion / applyRows の薄い委譲だけを見せる。型グループは 598 → 548 行。swift test 1297 件成功、ブランチ HEAD との swiftlint 差分は新規 0 件。
<!-- SECTION:FINAL_SUMMARY:END -->
