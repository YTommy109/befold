---
id: TASK-105
title: CLI経由の相対パス指定でファイルが開かずフォルダー表示になる
status: Done
assignee:
  - '@claude'
created_date: '2026-07-23 06:37'
updated_date: '2026-07-23 06:43'
labels: []
dependencies: []
priority: high
type: bug
ordinal: 51000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
befold file.mmd のように相対パスを指定すると、プレビューエリアがファイル内容ではなく親フォルダーのファイル一覧(FolderListingView)を表示する。絶対パスでは正常に動作する。

原因: openPaths() で URL(fileURLWithPath: "file.mmd") が作る URL の relativeString は "file.mmd" だが、サイドバーエントリーは parentDir.appendingPathComponent() 経由で作られ relativeString が "./file.mmd" になる。Swift の URL == は relativeString を比較するため不一致となり、PreviewTargetResolver.resolve() が selection をどのエントリーとも一致させられず .folder(currentDirectory) を返す。

副次的問題: CLI転送(CLIInstanceRouter.forward)でも相対パスがそのまま送られるため、受信側インスタンスのカレントディレクトリで解決され意図しないパスが開かれる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold ./file.mmd (相対パス)でファイルのプレビューが正しく表示される
- [x] #2 befold file.mmd (ファイル名のみ)でファイルのプレビューが正しく表示される
- [x] #3 既存インスタンスへの転送時にも相対パスが正しく解決される
- [x] #4 絶対パス指定の既存動作にリグレッションがない
- [x] #5 既存テスト(BefoldRootCommandTests/BefoldRootCommandIntegrationTests)がパスする
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. AppDelegate.launch(withInitialPaths:options:) の入口で paths を絶対パスに正規化する
   - URL(fileURLWithPath: path).standardizedFileURL.path で各パスを変換
   - これにより転送(forward)・新規起動(.launchAsNewInstance)の両方で絶対パスが使われる
2. テスト追加: 相対パスが正規化されることを検証するユニットテスト
3. swift test でリグレッションがないことを確認
4. 手動検証: befold --check で相対パスが正しく解決されることを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
AppDelegate.launch() の入口（forward() より前）で paths を URL(fileURLWithPath:).standardizedFileURL.path に正規化する1行を追加。BefoldRootCommandIntegrationTests に相対パスの --check テストを追加。swift test 全589テストパス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppDelegate.launch(withInitialPaths:options:) の入口で全パスを URL(fileURLWithPath:).standardizedFileURL.path で絶対パスに正規化した（1行追加）。これにより、(1) openPaths() で生成される URL の relativeString が FileManager のエントリー URL と一致し PreviewTargetResolver が正しく .file を返す、(2) CLIInstanceRouter.forward() が絶対パスを送信するため受信側の CWD に依存しなくなる。BefoldRootCommandIntegrationTests に相対パスの --check 統合テストを追加。swift test 全589テストパス。
<!-- SECTION:FINAL_SUMMARY:END -->
