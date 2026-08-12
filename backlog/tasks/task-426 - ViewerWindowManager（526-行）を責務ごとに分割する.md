---
id: TASK-426
title: ViewerWindowManager（526 行）を責務ごとに分割する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 10:09'
updated_date: '2026-08-11 23:52'
labels: []
dependencies: []
priority: high
type: chore
ordinal: 100500
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
- [x] #1 ViewerWindowManager.swift が file_length warning の 400 行以下になる
- [x] #2 型本体が type_body_length warning の 250 行以下になる
- [x] #3 openViewer のボディが function_body_length warning の 50 行以下になる
- [x] #4 分割は責務名がファイル名に表れる Type+Feature.swift の extension 形式で行う（行数回避のための機械的な分割にしない）
- [x] #5 新規ファイル追加後に xcodegen generate を実行し、xcodebuild でも通ることを確認する
- [x] #6 main との swiftlint 差分に「真の新規」が無い（/swiftlint-baseline の手順で確認。既存違反の解消は可）
- [x] #7 swift test が既存どおり通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ViewerWindowManager.swift はストアド依存 + init + makeDiffLoader + controllers 辞書の操作(register/detach)だけを残す composition root にする
2. 責務ごとに extension を切り出す: +OpenViewer(openViewer/reopenExistingWindow/初期状態解決) / +GlobalDisplay(全ウィンドウ一括反映) / +TabGroups(タブ結合・タブ構成スナップショット・Space 救出) / +RecentRepositories(最近使ったリポジトリ記録) / +SessionSync(辞書の付け替えとセッション記録・Delegate 準拠)
3. extension から触る private stored property を internal へ上げ、doc で用途を明示する。controllers の書き換えは基底ファイルの register/detach に閉じる(private(set) を維持)
4. openViewer は初期表示状態の解決とコントローラ生成をヘルパーへ抽出し 50 行以下にする
5. xcodegen generate → swift build / xcodebuild / swift test、swiftlint はベースライン差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ViewerWindowManager.swift(543 行)を 5 本の Type+Feature extension へ分割した。

- ViewerWindowManager.swift (154 行): 共有依存の stored property + init + makeDiffLoader + 辞書操作(register/detach)のみ。extension から辞書を直接書き換えられないよう controllers は private(set) のままで、書き換え口を register/detach の 2 つに閉じた
- +OpenViewer (144): openViewer / makeController / reopenExistingWindow。openViewer から初期表示状態の解決とコントローラ生成を makeController へ抽出し 58 → 26 行(swiftlint 計測)
- +GlobalDisplay (82): 全ウィンドウ一括反映(トグル・refreshAllSidebars/Toolbars・addBookmarks・applyCodeFontToAllWindows)
- +TabGroups (69): attachAsTab / tabWindows / makeTabGroup / tabGroup(of:) と Space 救出
- +RecentRepositories (67): 最近使ったリポジトリの記録
- +SessionSync (93): 辞書のキー付け替え・セッション記録・ViewerWindowControllerDelegate 準拠

FeatureGate. を参照する makeDiffLoader は基底ファイルに残したため、.swiftlint.yml の allowlist と FeatureGate.swift の doc は変更不要(FeatureGateEnumerationTests も緑)。

検証:
- swift build / xcodebuild build -scheme befold: いずれも成功(xcodegen generate 実行済み)
- swift test: 1431 tests / 212 suites 全passed
- swiftlint: origin/main を git archive で別ディレクトリへ展開して比較。差分は削除 3 件(file_length 543・function_body_length 58・type_body_length 298)のみで新規はゼロ
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowManager を責務ごとの 5 extension へ分割し、本体を 154 行の composition root に縮小した。file_length / type_body_length / function_body_length の 3 warning が消え、main との swiftlint 差分は削除 3 件・新規 0 件。swift build・xcodebuild・swift test(1431 passed)で確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
