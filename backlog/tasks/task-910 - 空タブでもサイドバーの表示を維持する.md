---
id: TASK-910
title: 空タブでもサイドバーの表示を維持する
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T06:38:00Z'
updated_date: '2026-11-07T07:37:00Z'
labels:
  - sidebar
  - tabs
  - ui
dependencies:
  - TASK-909
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
documentation:
  - docs/dev/viewer-ui.md
priority: high
type: bug
ordinal: 876000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーを表示した窓で ⌘T を押すと、新しい空タブにサイドバーが出ない（2026-11-07 実機確認）。サイドバーの表示はユーザーの操作で決まるものなので、新しいタブでも維持されるのが期待する動作。PR #750 の空タブは `NSHostingController` だけを持ち split view が無いため、タブを切り替えるだけでサイドバーが消えて本文の位置も動く。同じ理由で、`SidebarInheritance.seed(from:)` は起点が `ViewerWindowController` のときしか材料を返さないので、空タブを文書へ置き換えるとフォルダ一覧と展開状態を引き継げないはず（コードからの判断で未再現）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーを表示した窓で ⌘T またはタブバーの + を使うと、空タブにも起点と同じフォルダのサイドバーが表示される
- [x] #2 サイドバーを閉じた窓から開いた空タブではサイドバーが閉じている
- [x] #3 空タブのサイドバーでファイルを選ぶと、その空タブが同じ位置で文書タブに置き換わる
- [x] #4 空タブを文書へ置き換えたとき、サイドバーの開閉・一覧・ツリーの展開状態が保たれる
- [x] #5 起点の窓が無い ⌘T での動作が決まり、docs/dev/viewer-ui.md に記載されている
- [x] #6 ファイルを選ぶまで WebKit と文書のファイル監視を作らないという空タブの性質が保たれる（サイドバーの git 監視は文書タブと同じものを使う）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
方針: ViewerWindowController の fileURL は Optional にせず、BlankTabWindowController に ViewerSplitViewController を載せる。
1. BlankTabWindowController が SidebarNavigatorHost と FileListViewDelegate を実装する。SidebarNavigator は既存のものをそのまま使う
2. SidebarInheritance の取得元を ViewerWindowController 固定から小さなプロトコルへ広げ、空タブを起点にしても一覧・展開・開閉を引き継ぐ
3. 空タブを開くとき、起点の窓の開閉と一覧を引き継ぐ。起点が無ければ従来どおりサイドバーなし（列挙するフォルダが無いため）
4. ファイル選択は windowManager.openViewer(.currentTab, relativeTo: 空タブ) を通し、既存の置き換えと重複防止を共有する
5. 開閉の記録は文書タブと同じく利用者の操作だけ
6. ViewerStore と描画面を持たない構造のまま、ファイルを選ぶまで WebKit と文書の監視を作らない
7. git の比較基準は新しいタブと同じく既定値から始める
設計レビュー: 不変条件はスライド窓が起点にならないこと（既存の tabbingMode 判定）。兄弟判断は containsOpenWindow と Window メニュー同期で、どちらも空タブを含む。AppDelegate のサイドバー表示メニューは ActiveViewerProvider 経由なので空タブでは無効のままで、TASK-911 で扱う。粒度は窓ごと。型は 1 ファイル追加、新しい stored property は空タブ側だけ。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
制約: `ViewerWindowAssembler` のサイドバー組み立ては `ViewerWindowController` を前提にし、そのコントローラは fileURL が必須。新しい状態と経路を足す変更なので着手前に /review-design を回す。

受け入れ条件 6 は、サイドバーの git 監視を文書タブと共有する設計に合わせて『文書のファイル監視』へ書き換えた（ViewerStore も描画面も持たない構造で担保）。
決定: 起点の窓が無い ⌘T はサイドバーなし。フォルダ移動は文書タブと同じく先頭の行を選ぶので、ファイルなら空タブが置き換わる。git の比較基準は引き継がず既定値から始める。
責務レビューの指摘で SidebarNavigatorHost.currentFileURL を URL? にした（フォルダを返す案は契約違反で、履歴適用に潜在バグが残るため）。fileListDidSelectFile の失敗時は選択を外す。組み立ての重複（split view の配線）は Low のため残した。
実測: 修正を戻すと落ちることを確認（取得元を ViewerWindowController に戻す → seedReadsBlankTabSidebar ほか 3 件、makeSidebar を外す → selectingFileReplacesBlankInPlace ほか）。swift test 1981 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件。空タブのサイドバーの見た目と操作は実機で未確認。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
文書タブから開いた空タブにサイドバーを載せ、起点の開閉・フォルダ・一覧・展開を引き継ぐようにした。サイドバーで選んだファイルは同じ位置で文書タブに置き換わり、開閉と一覧はそのまま渡る。起点の窓が無い空タブはサイドバーを持たない。テスト 2084 件と Xcode ビルドが成功、swiftlint 新規 0 件。実機確認は未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
