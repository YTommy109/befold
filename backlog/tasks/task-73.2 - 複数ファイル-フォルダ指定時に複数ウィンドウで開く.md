---
id: TASK-73.2
title: 複数ファイル/フォルダ指定時に複数ウィンドウで開く
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 09:10'
updated_date: '2026-07-20 12:05'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 47000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
CLI からファイルまたはフォルダを複数指定して起動した場合、それぞれ独立した
ウィンドウで開けるようにする。TASK-73.1 の引数パーサー基盤に依存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold file1.mmd file2.md のように複数ファイルを指定すると、ファイルごとに別ウィンドウが開く
- [x] #2 befold folderA folderB のように複数フォルダを指定すると、フォルダごとに別ウィンドウが開く
- [x] #3 ファイルとフォルダを混在指定した場合もそれぞれ別ウィンドウで開く
- [x] #4 単一ファイル/フォルダ指定時の既存挙動が変わらない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-73.1 で AppDelegate.applicationDidFinishLaunching に initialPaths を1件ずつ openViewer(for:) するループを実装済みで、複数指定時の複数ウィンドウ化はその時点で既に成立していた(ViewerWindowManager.openViewer は正規化パスキーが異なれば毎回新規ウィンドウを作る設計のため)。CLIInstanceRouter.forward も複数URLをまとめてNSWorkspace.open(urls:)に渡すため、起動中インスタンスへの転送でも複数ウィンドウが開く。本タスクでは追加のプロダクションコード変更は不要と判断し、単純化の検討として新規の複数ウィンドウ専用ロジックは導入しなかった。ViewerWindowManagerTests に「複数ファイル/フォルダー(フォルダーは事前にresolveFileToOpenで解決)を順に開くとそれぞれ別ウィンドウになる」「単一指定では従来通り1ウィンドウ」の2テストを追加し、AC1〜4を裏付けた。フォルダー解決ロジック自体はDirectoryListerTests で既存カバー済み。検証: swift test 491件全パス、swiftlint新規違反なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
TASK-73.1 で実装済みの initialPaths ループと CLIInstanceRouter の複数URL転送により、複数ファイル/フォルダー指定時の複数ウィンドウ化は既に成立していたため、プロダクションコードの追加変更はなし。ViewerWindowManagerTests に複数ターゲット/単一ターゲットの検証テストを追加して全ACを自動テストで裏付けた(491テスト全パス)。
<!-- SECTION:FINAL_SUMMARY:END -->
