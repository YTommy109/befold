---
id: TASK-930.5
title: (e) 戻る・進むの履歴を意図で記録・再生する
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T00:13:12Z'
updated_date: '2026-11-25T11:07:14Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 867000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 2。いまの履歴は、記録時点の PreviewTarget（サイドバーの状態から導いた値）を写している。行の着地待ちの間に記録すると、ファイルを選んだまま「フォルダー提示」として残る（#794 の調査で実測）。意図を記録し、再生時は意図を書いてからサイドバーを合わせる形にする。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 履歴エントリは記録時の意図を持ち、サイドバーの状態から導いた値を写さない
- [x] #2 フォルダー一覧の履歴へ戻ったとき、別フォルダーへの移動を伴っても、一覧の着地を待たずに本文がその一覧になる
- [x] #3 ファイルの履歴へ戻ったとき、PreviewTarget の遷移に .folder が現れないことをテストで確かめる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
930.1 で記録は窓の意図(host.presentedTarget)を読み、再生は PreviewTarget を返す形になっている。残る穴は 3 つ:
1. 記録の時点: navigateToFolder は一覧の着地(performListing 完了)で recordHistory する。着地前に別のファイルを開くと着地時の記録が .file を読みフォルダー訪問が消え、世代の追い越しで着地しなければ記録されない。930.3 以降エントリは行に依存しないので、presentingFolder(url) の直後に同期で記録する
2. 記録の材料: currentPresentation の .file 分岐の ?? fileListModel.selection(サイドバーの選択)を撤去し、currentFileURL だけから作る。.folder(X) を X == currentDirectory で .folder(nil) に畳むのは残す(currentDirectory は再生でサイドバーを戻す先として既にエントリに持つ値で、提示の種別を選択から推論しているわけではない)
3. 再生の順序: いまは applyEntry(ファイル切替 → SidebarPostSwitchSync)の後で窓が present する。navigate(by:presenting:) に必須の presenting クロージャを渡し、ファイル切替の成功後・同期区間の前に呼ぶ(navigateToFolder の presentingFolder と同じ形。書く口は窓が持つ)。別文書を伴うフォルダーのエントリは performFileSwitch が .file を書くため同期区間内で .file → .folder と 2 回通る。host.performFileSwitch に提示を渡す口は足さない(サイドバー側に書く口を与えるため)。テストで遷移を固定し Notes に残す
4. テスト(窓レベル・実ファイル): AC#2 = 別フォルダーへのフォルダー一覧のエントリへ戻るとき、意図の onChange の時点で currentDirectory がまだ動いていない(意図 → サイドバー)・着地前に一覧が出ている。AC#3 = ファイルのエントリへ戻る(リスト/ツリー、別フォルダー、同じ文書で別ディレクトリ)で遷移に .folder が現れない。記録の時点 = フォルダーに入って着地前にファイルを開いても、フォルダー訪問が履歴に残る。それぞれ修正を戻して落ちることを確かめる
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: (1) SidebarNavigator.navigateToFolder は presentingFolder の直後に同期で recordHistory する(着地時の記録をやめた)。修正前は、着地前に別ファイルを開くと世代の追い越しで着地が捨てられ、フォルダー訪問が履歴から落ちていた(変異で実測)。(2) SidebarHistoryController.currentPresentation の .file 分岐から ?? fileListModel.selection を撤去した。.folder(X) を X == currentDirectory で .folder(nil) に畳むのは残した: currentDirectory はエントリが再生でサイドバーを戻す先として既に持つ値で、提示の種別をサイドバーの状態から推論するものではないため。(3) 再生は navigate(by:presenting:)(必須引数、navigateToFolder の presentingFolder と同じ形)で、ファイル切替の成功後・SidebarPostSwitchSync の前に意図を渡す(意図 → 本文 → サイドバー)。戻り値の PreviewTarget は撤去した。別の文書を伴うフォルダーのエントリでは performFileSwitch が .file を書いた直後に同じ同期区間で .folder へ書き直す。文書を出していた状態から戻るなら .file は変化にならず遷移は [.folder] の 1 回。host.performFileSwitch に提示を渡す口は足さない(サイドバー側に書く口を与えるため)。
テスト: 新規 ViewerWindowHistoryPresentationTests(実ファイル・ツリー/リスト)。AC#2 = 別フォルダーへのフォルダー一覧エントリへ戻る: await 前に .folder(other)、遷移は [.folder(other)]、書いた瞬間の currentDirectory は移動前。AC#3 = ファイルのエントリへ戻る(別フォルダーの別文書 / 同じ文書でフォルダー一覧から)で遷移に .folder が無く、await 前後とも文書。記録の時点 = フォルダーに入り着地前にファイルを開いても戻るとそのフォルダー一覧。変異 3 種(提示を同期区間の後へ戻す / 記録を着地へ戻す / ファイルのエントリでフォルダーを書く)で、それぞれ対応するテストがケースごとに落ちることを確認した。swift test --skip PDF 2006 件・--filter PDF 103 件通過。swiftlint は変更ファイルで 0 件。xcodegen generate 後に xcodebuild build -scheme befold 成功。型グループ: ViewerWindowController 963(-1)・SidebarNavigator 411 で例外表を実測値へ更新した。
文書: docs/dev/viewer-ui.md の「表示モードと履歴」に記録と再生の規則を足した。
範囲外(気付き): フォルダー行の選択(fileListDidSelectFolder)は履歴を記録しない。930.1 以前から同じで(8afabae9 の recordHistory 呼び出しは 3 か所)、j/k で行を移るたびに積むかどうかは挙動の判断になるため触れていない。実機(GUI)での確認は未実施。

追加: 別の文書を伴うフォルダーのエントリへ、フォルダー一覧の表示中から戻る経路(履歴メニューで 2 つ戻る)で遷移が [.file, .folder(other)] の 2 回になり、2 回目を書いた瞬間のサイドバーは移動前であることをテストで固定した(提示を同期区間の後へ戻す変異でツリー/リストとも落ちる)。.file は同じ同期区間内で書き直すため描画には出ない。
未担保の点: currentPresentation の ?? fileListModel.selection 撤去は、戻すと落ちるテストが無い(窓は常に fileURL を持つため .file 分岐で currentFileURL が nil にならず、到達しない分岐だった)。AC#1 は構造(材料に選択を読まない)と記録時点のテストで担保している。
気付き(要判断): 記録の呼び出しは窓の生成・syncAfterSwitch・navigateToFolder の 3 か所で、どれも .file か移動先フォルダー自身(.folder(nil))しか記録しない。HistoryPresentation.folder(非 nil の行 URL)は本番では作られない。フォルダー行の選択で記録するか、このケースを撤去するかはユーザー判断。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
戻る・進むの履歴を窓の意図で記録・再生するようにした(ADR 0013 決定 2)。記録はフォルダーに入った時点で同期に行い(一覧の着地を待っていたため、着地前に次の操作をするとフォルダー訪問が履歴から落ちていた)、サイドバーの選択を材料にしない。再生は記録した意図をサイドバーの同期より先に書く。検証: 新規 ViewerWindowHistoryPresentationTests(変異 3 種でそれぞれ落ちることを確認)、swift test 全件(PDF 含む)通過、xcodebuild 成功。実機確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
