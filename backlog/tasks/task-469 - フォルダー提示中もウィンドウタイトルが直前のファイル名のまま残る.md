---
id: TASK-469
title: フォルダー提示中もウィンドウタイトルが直前のファイル名のまま残る
status: To Do
assignee: []
created_date: '2026-08-13 06:27'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 692000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 現象

サイドバーでフォルダーを選択してプレビューエリアにフォルダー一覧を表示しているとき、ウィンドウタイトルが直前に開いていたファイル名のままになる。プロキシアイコン（`representedURL`）も同様に古いファイルを指したまま。

## 調査結果（原因）

タイトル設定の実装は 1 箇所（`BefoldApp/befold/App/ViewerWindowChrome.swift:52-55` の `ViewerWindowChrome.applyURL(_:to:)`）で、呼び出し元 3 箇所はすべて「ファイル URL が変わったとき」に限られる。

- ウィンドウ生成 `BefoldApp/befold/App/ViewerWindowChrome.swift:42`
- ファイル切替 `BefoldApp/befold/App/ViewerWindowController+FileNavigation.swift:63`（`performFileSwitch` → `applyURLToWindow` `同:119-122`）
- リネーム追随 `BefoldApp/befold/App/ViewerWindowController+FileNavigation.swift:79`

フォルダー選択は `fileListModel.selection` を書くだけでファイル URL は動かない（`BefoldApp/befold/Viewer/FileListView.swift:157-175`、`BefoldApp/befold/App/SidebarNavigator+FolderNavigation.swift:15-33` はウィンドウに触れない）。提示対象変化の唯一の通知点 `FileListModel.notifyPresentationTargetChangeIfNeeded`（`BefoldApp/befold/Viewer/FileListModel.swift:147-152`）の結線先 `BefoldApp/befold/App/ViewerWindowAssembler.swift:200-204` は、ツールバー再同期とサイドバーへのフォーカスのみでタイトル更新を行っていない。

## 方針の候補

タイトルの真実の源を `fileURL` ではなく `fileListModel.previewTarget`（`.folder(url)` ならそのフォルダー名）に切り替え、`ViewerWindowAssembler.swift:200-204` の提示対象変化フックからも `ViewerWindowChrome.applyURL` 相当を呼ぶ。導出点を 1 つに保つ点で ADR 0002 の方針に沿う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 フォルダー提示中はウィンドウタイトルがそのフォルダー名になる
- [ ] #2 フォルダー提示中は representedURL がそのフォルダーを指す
- [ ] #3 ファイル提示へ戻るとタイトル・representedURL がそのファイルに戻る
- [ ] #4 タイトル導出点が 1 箇所のままであること（ファイル用・フォルダー用に経路を二重化しない）
- [ ] #5 上記を検証するユニットテストを追加し、修正を戻すと落ちることを確認済み
<!-- AC:END -->
