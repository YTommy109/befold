---
id: TASK-930.2
title: (b) ファイルを開く経路を「意図 → 本文 → サイドバー」の順に揃える
status: Done
assignee:
  - '@claude'
created_date: '2026-11-25T00:12:51Z'
updated_date: '2026-11-25T01:05:01Z'
labels: []
dependencies:
  - TASK-930.1
documentation:
  - docs/adr/0013-presentation-intent-before-sidebar-sync.md
parent_task_id: TASK-930
priority: medium
type: bug
ordinal: 864000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ADR 0013 決定 4。入口ごとに、意図を書く・本文を読み込む・サイドバーを合わせる順序がばらばらで、開き直しや引き継ぎで本文がフォルダー一覧のまま残る経路がある（コード読解で見つけた候補。未実測）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 フォルダー一覧を表示中の窓で、すでに開いているファイルを CLI・Finder・Quick Open から開き直すと、本文にそのファイルが出る（同じ URL への切り替えでも意図を書く）
- [x] #2 元の窓の一覧を引き継いで新しいタブ・窓を開いたとき、新しいファイルが引き継いだ一覧に無くても、本文にフォルダー一覧が重ならない
- [x] #3 文書内リンク・隣のファイルへの移動・サイドバーのファイル選択・本文の一覧からのファイル選択が、同じ順序の経路を通る（経路を 1 本にまとめるか、順序を破れない形にする）
- [x] #4 上の各経路について、PreviewTarget の遷移に .folder が現れないことをテストで確かめる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 現状の整理(コード参照): 窓の中でファイルを切り替える経路は、switchFile(Quick Open・リンクの currentTab・サイドバーのファイル選択・本文の一覧・スライドの前後移動)と host.performFileSwitch(navigateToFolder の着地・履歴)の 2 本で、どちらも ViewerWindowController.performFileSwitch に集まる。930.1 でここが本文の読み込みより先に .file を書くようにしたので、「意図 → 本文 → サイドバー(syncAfterSwitch)」の順は既に構造で決まっている。新しい窓は生成時から .file
2. 穴は開き直し: ViewerWindowManager.openViewer の再利用ブロック(reusableController)は前面化と表示オプションの適用だけで意図を書かない。ここで existing.switchFile(to: url) を呼び、開き直しを同じ URL への切り替えとして同じ経路に乗せる
3. switchFile の同一 URL 分岐: フォルダー一覧を出していたときだけ .file を書き、sidebar.syncAfterSwitch でサイドバーの選択と表示中フォルダーを文書に合わせる(履歴も文書の提示として 1 件積まれる)。文書を出していたなら何もしない(読み込み直し・再同期を増やさない)
4. テスト: フォルダー一覧を出している状態から、サイドバーのファイル選択・リンク(openReference .currentTab)・Quick Open(switchFile)・navigateToFolder の先頭ファイル・履歴のファイル・開き直し(ViewerWindowManager.openViewer の再利用)を流し、意図の遷移が .file の 1 回だけでフォルダー提示へ戻らないことを確かめる。引き継ぎタブは、元の窓の一覧に無いファイルを newTab で開き、生成直後と着地後の両方でフォルダー提示でないことを確かめる
5. 型グループ: ViewerWindowController(959)の増分は例外表を実測値で更新する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
/review-design: 設計変更の指摘なし。開き直しの経路は hasReusableWindow → openViewer の再利用ブロックに集まり(DocumentOpener の prefersExistingWindow・Finder・最近使った項目)、窓は切り替えのたびに ViewerWindowSessionSync で現在 URL に付け替えられるため、再利用した窓の fileURL は開き直す URL と一致する。再利用ブロックでは表示オプションの適用・前面化より先に switchFile を呼ぶ(本文が最優先)。
実装: 再利用ブロックで existing.switchFile(to: url) を呼び、開き直しを同じ URL への切り替えとして同じ経路に乗せた。switchFile の同一 URL 分岐は、フォルダー一覧を出していたときだけ .file を書いて sidebar.syncAfterSwitch でサイドバーを文書へ合わせる(履歴に文書の提示が 1 件積まれる)。文書を出していたなら何もしない。
AC #3 の「同じ順序の経路」は構造で満たす: 窓の中でファイルを開く経路(switchFile: Quick Open・リンクの currentTab・サイドバーのファイル選択・本文の一覧・スライドの前後移動 / host.performFileSwitch: navigateToFolder の着地・履歴)はすべて performFileSwitch に集まり、そこが本文の読み込み(store.openFile)とサイドバーの同期(syncAfterSwitch)より先に .file を書く(930.1)。新しい窓は生成時から .file。
検証: ViewerWindowReopenPresentationTests(開き直しでフォルダー一覧から文書へ戻りサイドバーの選択も文書へ戻る／文書表示中の開き直しは提示も履歴も変えない／元の窓の一覧に無いファイルを newTab で開いても生成直後・着地後ともフォルダー提示にならない)と、ViewerWindowFileOpenPresentationTests にフォルダー一覧の表示中から 5 経路(Quick Open・サイドバーのファイル行・リンク・フォルダー移動の先頭ファイル・履歴)でファイルを開くと意図の遷移が [.file] だけになるテストを追加。修正(再利用ブロックと同一 URL 分岐)を戻すと開き直しのテストが 2 件の期待で落ちることを確認。5 経路と新しいタブのテストは 930.1 の構造で既に満たされており、修正を戻しても通る(回帰の見張り)。swift test --skip PDF 2002 件通過、swiftformat 差分なし、swiftlint ベースライン差分ゼロ、xcodebuild 成功。ViewerWindowController の型グループは 964(+5)で例外表を更新。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ファイルを開く経路を「意図 → 本文 → サイドバー」の順に揃えた(ADR 0013 段階 (b))。窓の中の切り替えは 930.1 で既に performFileSwitch に集まり構造で順序が決まっていたため、残る穴だった開き直し(CLI・Finder・最近使った項目・Quick Open で開いている文書を開く)を同じ経路に乗せた。ViewerWindowManager の再利用ブロックが switchFile を通り、switchFile の同一 URL 分岐はフォルダー一覧を出していたときだけ文書の提示へ戻してサイドバーを合わせる。テストで開き直し・引き継ぎタブ・5 経路を押さえ、修正を戻すと開き直しのテストが落ちることを確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
