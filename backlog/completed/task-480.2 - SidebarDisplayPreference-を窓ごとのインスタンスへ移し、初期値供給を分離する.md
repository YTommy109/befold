---
id: TASK-480.2
title: SidebarDisplayPreference を窓ごとのインスタンスへ移し、初期値供給を分離する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 08:01'
updated_date: '2026-08-14 11:26'
labels: []
dependencies:
  - TASK-480.1
parent_task_id: TASK-480
priority: high
type: task
ordinal: 90200
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在 SidebarDisplayPreference は全ウィンドウで 1 インスタンスを共有し(型の doc コメントに明記)、UserDefaults へ直接読み書きしている。これを窓ごとに 1 インスタンス持つ形へ変え、UserDefaults への読み書きは「新規ウィンドウ生成時に初期値を読む」「値の変更時に最新値として書き戻す」の 2 点に限定する。

既存キー(ShowHiddenFiles / ShowChangedFilesOnly / SidebarLayoutMode / SidebarSortOrder)は意味を変えずそのまま初期値として使うため、値の移行処理そのものは不要になる見込みだが、キーの意味が「全ウィンドウの現在値」から「新規ウィンドウの初期値」へ変わる。CLAUDE.md の UserDefaults キー節に従い、読み手の変化を洗って結論を Implementation Notes に残すこと。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバー表示 4 値の窓ごとのライブ値の真実の源が FileListModel 1 本に畳まれ、SidebarListingCoordinator.syncDisplayPreferences() による二重保持が無くなっている
- [x] #2 app-global の UserDefaults キー 4 つは、新規ウィンドウ生成時の初期値としてのみ読まれる
- [x] #3 4 値のいずれかを変更したウィンドウが、その値を UserDefaults へ書き戻す
- [x] #4 生きているウィンドウ側からグローバル保存値を読めない構造になっている(窓側は書き戻し用の口だけを持ち、読み取り API を持たない)
- [x] #5 既存キーの読み手の変化を洗い、移行の要否を明示的に決めた結論が Implementation Notes に記録されている
- [x] #6 窓ごとに独立していることを担保するテストがある(2 窓を作り一方だけ変更しても他方が変わらない)
- [x] #7 scripts/check-type-group-size.sh が通る(SidebarNavigator 393/400・FileListModel 384/400 のため閾値超過の余地が小さい)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. SidebarDisplaySettings(4 値の値型)と SidebarDisplayChange(変更の enum)を新設する
2. SidebarDisplayPreference を SidebarDisplayDefaults へ改名し、役割を「app-global の初期値供給＋書き戻し」に限定する。書き戻し口は SidebarDisplayDefaultsRecording プロトコルとして切り出す
3. FileListModel.init の sortOrder 引数を display: SidebarDisplaySettings へ差し替え、4 値すべてを窓ごとのライブ値として初期化する
4. SidebarNavigator.init の sidebarDisplayPreference 引数を displaySettings(値)＋displayDefaults(書き戻し口)へ差し替える。両者に既定値を持たせないことで渡し忘れをコンパイルエラーにする
5. SidebarListingCoordinator から syncDisplayPreferences() を削除し、4 値の変更の唯一の入口 applyDisplayChange(_:) を置く。ライブ値の更新・書き戻し・再列挙/展開破棄/git 再取得の非対称な後処理をここで対にする
6. SidebarNavigator は applyDisplayChange の薄い委譲 1 本に畳む(setSortOrder / syncDisplayPreferences の 2 本を置き換え、行数を増やさない)
7. GlobalDisplayBroadcaster は 480.2 の時点では既存の挙動(全窓へ配る・永続化する)を保つよう applyDisplayChange 経由へ書き換えるだけにする。アクティブ窓 1 つへの絞り込みと本型からの撤去は 480.3
8. 2 窓独立のテストと、窓側が読み取り API を持たないことの担保を入れる
9. swift build / swift test / check-type-group-size.sh / swiftformat / swiftlint ベースライン差分ゼロを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## UserDefaults キーの読み手の変化と移行の要否(AC#4 = CLAUDE.md の UserDefaults 節)

**結論: 移行は不要。stale キーも発生しない。**

読み手の実測(`grep -rn '"<キー名>"' BefoldApp/befold BefoldApp/befoldTests BefoldApp/BefoldKit BefoldApp/befoldCLI`):
4 キー(ShowHiddenFiles / ShowChangedFilesOnly / SidebarLayoutMode / SidebarSortOrder)とも
リテラルの出現は SidebarDisplayDefaults.swift:15-18 の 1 箇所のみ(ほかに
SidebarDisplayDefaultsTests.swift:76 が壊れた値のフォールバック検証で 1 件)。
読み手が 0 になったキーは無い。

キー名・値の型・値の domain はいずれも不変(Bool 2 つ、rawValue 文字列 2 つ)。
変わったのは**意味**だけで、「全ウィンドウの現在値」→「次に開く窓の初期値」。
既存ユーザーの保存値はそのまま新しい意味の値として妥当なため、写し替える処理は要らない。
削除すべき旧キーも無い(4 キーとも残して使い続ける)。

## 案 B を採った理由(/review-design の結果、ユーザー承認済み)

当初 AC は「SidebarDisplayPreference を窓ごとに生成する」(案 A)だったが、調査で
sortOrder が既に窓ごとのライブ値(真実の源 = FileListModel.sortOrder)になっており、
案 A では窓ごとに SidebarDisplayPreference と FileListModel ミラーという真実の源が
2 つ残ることが分かった。残り 3 値を sortOrder と同じ形へ揃える案 B を採り、AC を書き換えた。

## 構造による担保(AC#4)

- SidebarListingCoordinator が持つのは SidebarDisplayDefaultsRecording(record のみ、getter 無し)。
- 既定値を読むのは SidebarNavigator.init の 1 回だけ。init は displayDefaults を**保持しない**ため、
  窓が生きている間に読み直す経路はコンパイル時に作れない。

## テストが回帰を捕まえることの確認(memory: verify-tests-fail-without-the-fix)

新規 SidebarDisplayIndependenceTests を、修正を戻した状態で 2 回実測した。
- 回帰 A(列挙のたびに保存値を読み直す = 旧 syncDisplayPreferences 相当を復活): 
  「一方の窓で変えた表示設定は…もう一方の窓にも届かない」が hidden / changedOnly / layout の 3 値で失敗。
  sortOrder は旧ミラー同期の対象外だったため落ちないのが正しい。
- 回帰 B(recordSettings() の呼び出しを落とす):
  「変えた値は保存され、その後に開いた窓の初期値になる」が 4 値すべてで失敗(8 issues)。

## 480.3 へ持ち越した暫定形

- GlobalDisplayBroadcaster.applySidebarDisplayChangeToAllWindows(_:) — 挙動を変えないため全窓へ配る形を残した。
  なお本型は SidebarDisplayDefaults を保持しなくなったので 480.3 AC#5 は先に満たしている。
- ViewerWindowManager.setHiddenFilesFromCLI(_:) — 呼び出し元(DocumentOpener / SessionRestorer)が
  ウィンドウを開く前に呼ぶため、既定値の書き換えと開いている窓への反映の両方を行う暫定形。
  480.3 で --sort と同じ「その起動限りの上書き」へ揃えて撤去する。
- AppDelegate.validateMenuItem と AppQuickOpenEnvironment は暫定で displayDefaults.settings を読む(480.3 で窓側へ)。

## 検証

swift build 成功 / swift test 1510 tests in 239 suites passed /
scripts/check-type-group-size.sh exit=0(ViewerWindowManager 398・FileListModel 395 と余裕は小さい。
480.3 で setHiddenFilesFromCLI を撤去すると ViewerWindowManager は 17 行減る) /
swiftlint は main とのベースライン差分ゼロ(両者 54 件で diff 出力なし) /
swiftformat fix モード実行済み / scripts/check-doc-symbols.sh exit=0
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー表示 4 値の真実の源を窓ごとの FileListModel 1 本へ畳んだ。SidebarDisplayPreference は SidebarDisplayDefaults へ改名し、役割を『新規ウィンドウの初期値供給＋書き戻し』に限定。窓の内側へ渡すのは読み取りを持たない SidebarDisplayDefaultsRecording だけで、既定値を読むのは SidebarNavigator.init の 1 回のみ(init は保持しないので以後読み直せない)。二重保持していた syncDisplayPreferences() を削除し、4 値の変更を SidebarListingCoordinator.applyDisplayChange(_:) の 1 本へ集約(値ごとに異なる後処理——再列挙 / 展開の破棄 / git の取り直し——をここで対にした)。UserDefaults 4 キーは名前・型・値の domain とも不変で、読み手は SidebarDisplayDefaults 1 箇所のみ(grep で実測)のため移行不要。検証: swift test 1510 tests passed、swiftlint は main とのベースライン差分ゼロ(54 件で一致)、check-type-group-size.sh exit=0、新規 SidebarDisplayIndependenceTests が修正を戻すと落ちることを 2 種の回帰で実測(読み直し復活で 3 値、書き戻し削除で 4 値)。
<!-- SECTION:FINAL_SUMMARY:END -->
