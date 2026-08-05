---
id: TASK-282
title: サイドバーヘッダーに「変更されたファイルのみ表示」のアイコンボタンを追加する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-04 06:29'
updated_date: '2026-08-04 06:39'
labels: []
dependencies: []
priority: medium
ordinal: 472000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-264 で追加した git 変更ファイル絞り込みは現在 View メニュー(⌘⌃G)からしか操作できない。不可視ファイルトグルと同様に、サイドバーヘッダーのアイコンボタンからも切り替えられるようにする。

方針(ユーザー確認済み・2026-08-04): 既存の eye ボタンをプルダウン化するのではなく、4 つ目の独立したトグルボタンを追加する。「不可視を含める」と「変更のみに絞る」は独立した軸で、頻繁に往復させるため、両方の状態が一目で見えることと 1 クリックで切り替わることを優先する。項目が増えたら将来プルダウンへ集約する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 サイドバーヘッダーのアイコンボタンで「変更されたファイルのみ表示」を切り替えられる
- [x] #2 ボタンの ON/OFF が既存ボタンと同じ様式(アイコン切替 + primary/secondary)で判別できる
- [x] #3 アイコンボタンからの切り替えも全ウィンドウへ連動し UserDefaults に永続化される(メニュー経路と同じ結果になる)
- [x] #4 FeatureGate.inProgressFeaturesEnabled が false のときボタンは露出しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. FileListView に onToggleChangedFilesOnly: (() -> Void)? を追加し、nil ならボタンを出さない(露出点を 1 箇所に保つ)。
2. ViewerWindowController.makeChangedFilesOnlyToggle() で FeatureGate を判定し、無効なら nil を返す。
3. ViewerWindowControllerDelegate に viewerWindowDidToggleChangedFilesOnly を足し、ViewerWindowManager.toggleChangedFilesOnly() へ繋ぐ(メニュー経路と同じ出口)。
4. アイコンは arrow.triangle.branch、ON/OFF は既存ボタンと同じ primary/secondary。ツールチップは sidebar.changedFilesOnly.show/hide。
5. テストは既存の隠しファイル流儀に合わせ、トリガー経路のパラメタライズドテストへアイコンボタン経路を足す。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: ヘッダー 4 つ目のトグルボタンとして追加(eye ボタンのプルダウン化は見送り。不可視/変更のみは独立した軸で、1 クリックと状態の可視性を優先。項目が増えたら将来集約する)。FeatureGate 判定はクロージャを nil にするかどうかの 1 箇所に閉じ、FileListView 側は nil で非表示にするだけにした。

検証: swift test 1059 passed。全ウィンドウ連動テストをパラメタライズド化し、メニュー(⌘⌃G)とアイコンボタン経路の 2 ケースが通ることを確認(実行ログで 2 test cases を確認)。xcodebuild build -scheme befold 成功、swiftformat 0 件、swiftlint は main とルール差分ゼロ。アプリを起動して目視確認できる状態にした。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーヘッダーに「変更されたファイルのみ表示」のトグルボタン(arrow.triangle.branch)を追加した。メニュー ⌘⌃G と同じ ViewerWindowManager.toggleChangedFilesOnly() へ合流するため、全ウィンドウ連動と UserDefaults 永続化は共通。FeatureGate 無効時はクロージャが nil になりボタンごと出ない。swift test 1059 passed とトリガー経路 2 種のパラメタライズドテストで検証した。
<!-- SECTION:FINAL_SUMMARY:END -->
