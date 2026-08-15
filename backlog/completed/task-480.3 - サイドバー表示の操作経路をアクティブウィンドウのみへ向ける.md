---
id: TASK-480.3
title: サイドバー表示の操作経路をアクティブウィンドウのみへ向ける
status: Done
assignee:
  - '@claude'
created_date: '2026-08-14 08:02'
updated_date: '2026-08-14 11:45'
labels: []
dependencies:
  - TASK-480.2
parent_task_id: TASK-480
priority: high
type: task
ordinal: 90300
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
GlobalDisplayBroadcaster からサイドバー表示 4 値の一括反映を外し、操作経路をアクティブウィンドウ 1 つへ向ける。対象の経路は次のとおり。

- メニュー(View メニューの ⌃⌘T / 不可視ファイル / 変更ファイルのみ / 並び順)と AppDelegate の @objc アクション、および validateMenuItem のチェック状態
- サイドバーヘッダーのアイコンボタン(SidebarHeaderControlsModel 経由)
- CLI の --hidden-files / --no-hidden-files(setHiddenFiles)。CLI 起動時に開く対象ウィンドウへ適用する形にする

GlobalDisplayBroadcaster の doc コメントは「窓ごとのライブ値はここから配ってはならない」と定めており、その禁止を型の依存で担保している。サイドバー 4 値も同じ扱いへ移るため、この型が SidebarDisplayPreference を持たなくなる形を目指す(持たなければ配れない、という構造で担保する)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ⌃⌘T・不可視ファイル・変更ファイルのみ・並び順の変更が、アクティブウィンドウのサイドバーだけに反映される
- [x] #2 View メニューのチェック状態がアクティブウィンドウの値を反映する
- [x] #3 サイドバーヘッダーのアイコンボタンからの操作も同じ窓だけに閉じる
- [x] #4 CLI の --hidden-files / --no-hidden-files が、その起動で開くウィンドウにだけ適用され、UserDefaults の既定値を書き換えない(--sort と同じ「その起動限りの上書き」に揃える)
- [x] #5 GlobalDisplayBroadcaster が SidebarDisplayDefaults(旧 SidebarDisplayPreference)を保持しない
- [x] #6 AppQuickOpenEnvironment.includingHiddenFiles が、Quick Open を開いたウィンドウの値を読む
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. サイドバーヘッダーの 3 トグルを delegate 経由から controller.sidebar.applyDisplayChange(_:) の直接呼び出しへ変え、使われなくなる viewerWindowDidToggleHiddenFiles / ChangedFilesOnly / SidebarTreeLayout を ViewerWindowControllerDelegate から撤去する
2. AppDelegate の @objc アクション 3 本を ActiveViewerProvider 経由のアクティブウィンドウ 1 つへ向ける
3. validateMenuItem のチェック状態をアクティブウィンドウの FileListModel から読む。ウィンドウが無いときは項目を無効化する(操作対象が無いので)
4. CLI --hidden-files を --sort と同じ「その起動限りの窓ローカル上書き」へ揃える。新規ウィンドウは ViewerWindowController.init の override 引数、既存ウィンドウは ViewerDisplayOptionsApplier。既定値は書き換えない
5. ViewerWindowManager.setHiddenFilesFromCLI と GlobalDisplayBroadcaster.applySidebarDisplayChangeToAllWindows を撤去する
6. AppQuickOpenEnvironment を SidebarDisplayDefaults 依存から includingHiddenFiles: Bool の受け取りへ変え、QuickOpenCoordinator が activeViewer の値を渡す
7. 全窓へ伝播することを固定していた既存テストを、1 窓だけに閉じることの検証へ書き換える。CLI の非永続とメニュー無効化のテストを足す
8. swift build / swift test / check-type-group-size.sh / swiftlint ベースライン差分ゼロを確認する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-480.2 の /review-design で 2 点をスコープへ追加した(2026-08-14、ユーザー承認済み)。
1. AppQuickOpenEnvironment.swift:39 の includingHiddenFiles が app-global 値を読んでおり、当初どの AC にも入っていなかった。窓ごと化後に唯一のグローバル読み手として残るため AC#6 として追加。
2. CLI --hidden-files は現在 GlobalDisplayBroadcaster.setHiddenFiles で UserDefaults を書き換えて全窓へ配る(GlobalDisplayBroadcaster.swift:69-80)。一方 --sort は「その起動限りの上書きで共有設定を書き換えない」(ViewerDisplayOptionsApplier.swift:28-33)。ADR 0002 の CLI 規則は後者なので --sort へ揃える(挙動変更)。CLIOpenOptions.swift:36 の doc コメント「これだけはアプリ全体設定のため対象を要さない」も書き換え対象。

## 実装の要点

- **入口を 1 本に畳んだ。** メニュー(AppDelegate の @objc 3 本)もサイドバーヘッダーのボタンも、
  同じ SidebarNavigator.applyDisplayChange(_:) を通る。以前ヘッダーは
  delegate → ViewerWindowManager → GlobalDisplayBroadcaster と窓の外を往復していたが、
  配る先が 1 窓になったため往復の理由が消え、ViewerWindowControllerDelegate から
  viewerWindowDidToggleHiddenFiles / ChangedFilesOnly / SidebarTreeLayout の 3 本を撤去した。
- **メニューのチェック状態は SidebarDisplayMenuState へ切り出した。** NSApp.mainWindow への依存を
  呼び出し側に残し、判定(窓が無ければ無効化する扱いを含む)を headless に検証できるようにした。
- **CLI --hidden-files を --sort と同じ扱いに揃えた。** 新規ウィンドウは
  ViewerWindowController.init の override 引数、既存ウィンドウは ViewerDisplayOptionsApplier。
  既定値は書き換えない。パス無し起動(--hidden-files 単独)だけは適用先の窓が決まらないため、
  DocumentOpener がアクティブウィンドウへ適用する(CLI のパース規則 requiresPaths は変えていない)。
- CLI 由来の上書きは SidebarDisplayOverrides(sortOrder / showHiddenFiles)へまとめた。
  個別引数のままだと assembler の引数が 6 個になり swiftlint の function_parameter_count が鳴る
  実測があり、経路が増えるたびに片方だけ通し忘れる形(TASK-413 と同型)も避けられる。
- 撤去: GlobalDisplayBroadcaster.applySidebarDisplayChangeToAllWindows /
  ViewerWindowManager.setHiddenFilesFromCLI(どちらも 480.2 の暫定形)。

## 挙動変更(ユーザーに見える差分)

1. サイドバー表示 4 値の変更が、操作したウィンドウだけに効く(従来は全ウィンドウ)。
2. CLI --hidden-files / --no-hidden-files が保存された既定値を書き換えなくなった。
   従来は一度指定するとそれ以降に開くすべての窓へ効き続けた。
3. ビューアウィンドウが 1 枚も無いとき、View メニューのサイドバー表示 3 項目が無効になる
   (届け先の窓が無いため)。

## テストが回帰を捕まえることの確認

- ViewerWindowManagerIntegrationTests の「全ウィンドウへ同時に反映される」3 テストを
  「操作したウィンドウだけに反映される」1 テスト(4 値のパラメータ化)へ書き換えた。
  もう一方の窓は refreshFileList してから確認するため、取り直しの契機で保存値を読み直す形へ
  戻すと落ちる。
- SessionRestorerTests の CLI 非永続テストは、SidebarNavigator.init に
  displayDefaults.record(initialSettings) を足した状態で実測して落ちることを確認した
  (showHiddenFiles: true が既定値へ書かれて失敗)。

## 検証

swift build 成功 / swift test 1511 tests in 240 suites passed /
swiftlint は main とのベースライン差分ゼロ(両者 54 件、diff 出力なし。途中 2 件
——ViewerDisplayOptionsApplier の opening_brace と ViewerWindowAssembler の
function_parameter_count——が出たため、多行条件の解消と SidebarDisplayOverrides の導入で潰した) /
scripts/check-type-group-size.sh exit=0(FileListModel 396・SidebarNavigator 383・AppDelegate 376・
ViewerWindowManager 369) / markdownlint-cli2 0 issues / scripts/check-doc-symbols.sh exit=0

## 現在仕様への追随

docs/dev/native-app-design.md を更新した(GlobalDisplayBroadcaster の責務行、
実在しない型名だった HiddenFilesPreference の行を SidebarDisplayDefaults へ差し替え、
モジュールツリーのコメント、サイドバー節に 4 値の粒度と唯一の入口を追記)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバー表示 4 値の操作経路をアクティブウィンドウ 1 つへ向けた。メニュー・サイドバーヘッダー・CLI がすべて SidebarNavigator.applyDisplayChange(_:) の 1 本へ合流し、delegate 経由で ViewerWindowManager を往復していたヘッダーの経路と、GlobalDisplayBroadcaster / ViewerWindowManager 側の一括反映 API を撤去。メニューのチェック状態は SidebarDisplayMenuState へ切り出してアクティブウィンドウの値を映し、窓が無ければ項目を無効化する。CLI --hidden-files は --sort と同じ「その起動限りの窓単位の上書き」へ揃え、既定値を書き換えない。Quick Open も操作元ウィンドウの値を読む。検証: swift test 1511 tests passed、swiftlint は main とのベースライン差分ゼロ、check-type-group-size.sh exit=0、書き換えた 2 テストが回帰(保存値の読み直し / CLI の永続化)を実際に捕まえることを実測で確認。
<!-- SECTION:FINAL_SUMMARY:END -->
