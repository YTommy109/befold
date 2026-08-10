---
id: TASK-426
title: ViewerWindowManager（526 行）を責務ごとに分割する
status: To Do
assignee: []
created_date: '2026-08-10 10:09'
labels: []
dependencies: []
priority: medium
type: chore
ordinal: 109000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldApp/befold/App/ViewerWindowManager.swift は 526 行（wc -l 実測）で、BefoldApp/.swiftlint.yml の閾値に対して 3 件の warning が出続けている（TASK-412 の作業中に、修正前の HEAD 版を同一 config で測って確認した）。

- file_length: 526 > warning 400（error は 1000 なのでビルドを落とす切迫はない）
- type_body_length: クラス本体 291 > warning 250（error 350 まで残り 59 行。3 件のうちここが最も近い）
- function_body_length: openViewer が 58 > warning 50（error 100）

TASK-411 で分割した ViewerWindowController と違い、こちらはまだ Type+Feature.swift の extension が 1 本も切られておらず、1 ファイルが次をすべて所有している。

- ウィンドウ生成と辞書管理（openViewer / detach / remapController / window(forPath:) / viewerPath(of:)）
- タブグループの組み立て（attachAsTab / tabWindows / makeTabGroup / tabGroup(of:)）
- アプリ全体の表示設定を全ウィンドウへ配る一括反映（toggleHiddenFiles / toggleChangedFilesOnly / toggleSidebarLayoutMode / setHiddenFiles / addBookmarks / applyCodeFontToAllWindows / applyDisplayOverrides / refreshAllSidebars / refreshAllToolbars）
- 「最近使ったリポジトリ」の記録（recordRecentRepositoryIfNeeded / applyRecentRepository / recordRecentRepositoryTabGroup / recordAllRecentRepositoryTabGroups）
- セッション記録の更新と ViewerWindowControllerDelegate 準拠（noteClosedIfNoWindowRemains ほか）
- Space からはぐれたウィンドウの救出（isDetachedFromSpace / rescueWindowsDetachedFromSpace）

加えて init が 20 個の依存を受け取る composition root を兼ねている。

切迫度は TASK-411（error まで残り 22 行）ほど高くないため優先度は medium。ただし機能追加のたびに type_body_length の残り 59 行を削ることになるので、次にこの型へ機能を足すタスクの前に済ませたい。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ViewerWindowManager.swift が file_length warning の 400 行以下になる
- [ ] #2 型本体が type_body_length warning の 250 行以下になる
- [ ] #3 openViewer のボディが function_body_length warning の 50 行以下になる
- [ ] #4 分割は責務名がファイル名に表れる Type+Feature.swift の extension 形式で行う（行数回避のための機械的な分割にしない）
- [ ] #5 新規ファイル追加後に xcodegen generate を実行し、xcodebuild でも通ることを確認する
- [ ] #6 main との swiftlint 差分に「真の新規」が無い（/swiftlint-baseline の手順で確認。既存違反の解消は可）
- [ ] #7 swift test が既存どおり通る
<!-- AC:END -->
