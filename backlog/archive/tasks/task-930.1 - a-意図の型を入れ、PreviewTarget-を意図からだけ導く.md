---
id: TASK-930.1
title: (a) 意図の型を入れ、PreviewTarget を意図からだけ導く
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T00:12:30Z'
updated_date: '2026-11-25T00:53:47Z'
labels: []
dependencies: []
references:
  - https://github.com/YTommy109/befold/issues/794
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: high
type: bug
ordinal: 863000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 1〜3 の土台。いまは PreviewTargetResolver が選択・行・一覧の着地状況から本文の表示を導いており、行が無いと .folder に倒れる。GitHub #794（ツリー表示の Quick Open で本文に一覧が一瞬重なる）はここで直る。既存の入口の挙動（フォルダーに入ったときの自動選択など）は変えず、意図の書き手を既存の入口へ配線するだけにとどめる。挙動の変更は (b)〜(e) で行う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 窓ごとの意図（文書 URL かフォルダー URL）を 1 つの値で持ち、PreviewTarget はそこからだけ導かれる（選択・行・hasLoadedEntries・isListingCurrent を材料にしない）
- [x] #2 サイドバーの同期処理（一覧の再読み込み・展開と折りたたみ・レイアウト切り替え・不可視ファイル切り替え・フォルダー移動の後追い）からは意図を書けない構造になっている（書き込み口に届かない、または必須引数で入口を区別する）
- [x] #3 ツリー表示・リスト表示の両方で、Quick Open から畳まれたサブフォルダー内／別フォルダー／同じフォルダーの行の無いファイルへ切り替えたとき、子リストの着地前・着地後のどちらでも本文がフォルダー提示にならないことをテストで確かめる。修正を戻すとそのテストが落ちることも確かめる
- [x] #4 開いているファイルの名前変更の後、再読み込みの着地で PreviewTarget が .folder を通らない（テストで確かめる）
- [x] #5 .undetermined を残すか消すかを決め、理由を Notes に残す
- [x] #6 実機で、ツリー表示の ⌘P から畳まれたサブフォルダー内のファイルを開いても、フォルダー一覧が重ならない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 意図の置き場: 新しい型 PresentationIntent（@MainActor @Observable、befold/Viewer/）に private(set) var target: PreviewTarget（.file / .folder(URL)）と present(_:)、変化時の onChange を持たせる。ViewerWindowController が所有し、読むのは ViewerContentView・capabilities・タイトル・履歴（host 経由の読み取り専用）。SidebarNavigator・SidebarListingCoordinator・SidebarTreePresenter・SidebarLayoutTransition・FileListModel には渡さない（サイドバーの同期処理から書けない構造）
2. 書き手（すべて ViewerWindowController 側）:
   - 窓の生成時 = .file（窓は必ず文書で生成される）
   - performFileSwitch の成功時 = .file（Quick Open・リンク・サイドバーのファイル選択・スライド移動・navigateToFolder 着地のファイル選択・履歴のファイル再生がここを通る）
   - FileListViewDelegate に fileListDidSelectFolder(_:) を足し、FileListView の選択経路（クリック・commitSelection・j/k・ツリーの ← 親行）がフォルダー行を選んだら .folder(url)。空タブは何もしない
   - navigateToFolder の着地: 最終的な選択がファイルへの切り替えでなければ .folder(選択したフォルダー行 ?? 移動先)。navigator.navigateToFolder に書き込み用クロージャを渡し、recordHistory より前に呼ぶ
   - 履歴の再生: navigate(by:) が適用したエントリの提示を返し、.folder(url?) なら .folder(url ?? entry.directory)
3. 導出の撤去: PreviewTargetResolver・FileListModel.previewTarget / onPresentationTargetChange / lastNotifiedTarget と PreviewTarget.undetermined を削除する（窓は生成時から意図を持つため、未確定の状態が無くなる）。onPresentationTargetChange の消費（refreshUIState・タイトル・フォルダー時のサイドバーフォーカス）は PresentationIntent.onChange へ移す
4. 履歴の記録: SidebarHistoryController.currentPresentation は host.presentedTarget を読む。.folder(X) は X == currentDirectory なら .folder(nil)、それ以外は .folder(X)
5. テスト: 導出のテスト（PreviewTargetResolverTests・FileListModelPreviewTargetTests）を意図のテストへ置き換える。ViewerWindowController（実ファイル）で、ツリー・リストそれぞれに Quick Open 相当の switchFile（畳まれたサブフォルダー内・別フォルダー・同じフォルダーの行の無いファイル）と名前変更を流し、子リストの着地前・着地後ともにフォルダー提示にならないこと、タイトルがフォルダー名へ一度も変わらないこと（KVO で記録）を確かめる。旧実装でこのテストが落ちることを確かめる
6. 型グループ行数: ViewerWindowController は 937/939 に張り付いているため、増分は PresentationIntent 側へ寄せ、残る増分は例外表を実測値で更新する

7. /review-design の反映: (a) サイドバーの同期処理が意図を書けないことを、構造（PresentationIntent を sidebar 系の型へ渡さない）に加えて振る舞いのテストで押さえる（再読み込み・ツリーの折りたたみ・レイアウト切り替えで意図が変わらない）。(b) present は同値なら何もしない（onChange の再同期を増やさない）。(c) フォルダー一覧の表示中にそのフォルダーが消えた場合は、本文を文書へ戻さず一覧の失敗表示のままにする（FolderListingSourceResolver が任意の URL を自前列挙できることを確認済み）。挙動の変化として Notes に残す。(d) 型グループの上限超過は例外表を実測値で更新する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 本文の意図を PresentationIntent(befold/Viewer/PresentationIntent.swift)に持たせ、ViewerWindowController が所有する。PreviewTargetResolver と FileListModel.previewTarget / onPresentationTargetChange / lastNotifiedTarget、FileListEntryIndex.entry(for:selectionPathKey:) と byID を削除した。書き手: 窓の生成時 .file、performFileSwitch の成功、switchFile の同一 URL(フォルダー一覧の表示中に開いている文書を選び直したとき)、FileListViewDelegate.fileListDidSelectFolder(FileListView.presentSelected から。クリック・commitSelection・j/k・ツリーの ← 親行)、navigateToFolder の着地(必須引数 presentingFolder)、履歴の再生(navigateHistory が適用したエントリの PreviewTarget を返す)。
.undetermined は削除した。理由: 窓は必ず文書を開いて生成されるため、生成時から意図は .file で確定している。未確定は「サイドバーの一覧が届いたか」を本文の材料にしていたことの副産物で、その材料を使わなくなった。初期タイトル(ViewerWindowChrome)と履歴の記録(.undetermined をファイル提示として記録していた分岐)も .file に揃えた。
実装中に見つかった 2 件(いずれも選択から導いていた頃は自然に満たされていた見え方): (1) フォルダー一覧の表示中に開いている文書の行を選び直すと switchFile が同一 URL で早期 return し一覧が残る → 早期 return の前に .file を書く。(2) 開いている文書と同じファイルの履歴エントリへ戻ると切替が起きず .file が書かれない → navigateHistory の戻り値をフォルダー URL から PreviewTarget に変えた(SidebarNavigatorHistoryTests が検知)。
挙動の変化: フォルダー一覧の表示中にそのフォルダーが消えたり、ツリーで祖先を畳んだりしても、本文は文書へ戻らずフォルダー一覧のまま(サイドバーの同期は意図を書かないため)。
検証: 新規 ViewerWindowFileOpenPresentationTests(実ファイル・ツリー/リスト)。修正前のコード(origin/main 相当)で実行し、畳まれたサブフォルダー内(ツリー)・同じフォルダーの行の無いファイル(ツリー/リスト。リストは着地後も一覧が残る)・名前変更(ツリー/リスト)の 3 経路が落ちることを実測した(当時はタイトルの KVO で記録。swiftlint の block_based_kvo を避けるため、最終版は意図の onChange を連鎖して記録する形に置き換え、switchFile に意図的なフォルダー提示を差し込む変異で 6 ケースすべてが落ちることを確認)。別フォルダーのケースは修正前から通る(一覧未着の間は .undetermined で本文を出していた)。サイドバーの同期(取り直し・折りたたみ・不可視ファイル切り替え・表示形式切り替え)で意図が変わらないことも同スイートで確かめる。swift test --skip PDF 1998 件・--filter PDF 103 件すべて通過。swiftformat 差分なし、swiftlint は main とのベースライン差分ゼロ。xcodegen generate 後に xcodebuild build -scheme befold 成功。型グループ: ViewerWindowController 959(+22)・SidebarNavigator 438(+7)で例外表を実測値へ更新、FileListModel は 400 → 352。

AC #1 の「文書 URL かフォルダー URL」について: 文書の URL は意図に持たせず .file だけを持つ。窓の現在 URL(ViewerStore / CurrentDocumentRef)と二重にしないため。フォルダーは .folder(URL) で URL を持つ。

AC #6 実機確認(2026-11-25): インストール版 befold を終了し、開発ビルド(Debug, .build/xcode)を単独で起動した。一時的に present / タイトル / syncAfterSwitch へ NSLog を入れてビルドし、README.md の窓(ツリー表示、ルート = リポジトリ)で System Events から ⌘P → docs/dev/file-type-display.md を開いた。ログ: 'sync file-type-display.md rowMissing=1 revealsInTree=1 layout=tree'(行の無い、畳まれた docs 配下へのツリー内展開 = #794 の経路)。提示の変化は 'present file (current file)' の 1 件だけで、タイトルも file-type-display.md の 1 回だけ。展開の着地後(3 秒)まで .folder の提示もフォルダー名のタイトルも 0 件。計測後に NSLog は撤去済み。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
本文に何を出すか(PreviewTarget)を、サイドバーの選択と一覧の行から導くのをやめ、窓ごとの PresentationIntent に持たせた(ADR 0013 段階 (a))。書くのは利用者の操作を受けた入口(窓の生成・ファイル切替・同一文書の選び直し・フォルダー行の選択・フォルダー移動の着地・履歴の再生)だけで、サイドバー側の型は参照を持たないため同期処理から書けない。PreviewTargetResolver・FileListModel の導出と通知・PreviewTarget.undetermined を削除した。GitHub #794(ツリー表示の Quick Open で本文に一覧が一瞬重なる)に加え、同じフォルダーの行の無いファイルを開いたとき(リスト表示では着地後も残った)と名前変更のときに本文がフォルダー提示を通る不具合も直った(修正前のコードで新テストが落ちることを実測)。検証: 新規 ViewerWindowFileOpenPresentationTests(実ファイル・ツリー/リスト、変異検査込み)、swift test 全件(PDF を含む)通過、swiftlint ベースライン差分ゼロ、xcodebuild 成功、実機(開発ビルド単独)で #794 の経路の提示ログを確認。挙動の変化: フォルダー一覧の表示中にそのフォルダーが消えても、祖先を畳んでも、本文は文書へ戻らない。残り: (b)〜(e) は TASK-930.2〜930.5。
<!-- SECTION:FINAL_SUMMARY:END -->
