---
id: TASK-73.4
title: bookmark サブコマンドでブックマークを追加できるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-19 09:11'
updated_date: '2026-07-20 12:40'
labels: []
dependencies:
  - TASK-73.1
parent_task_id: TASK-73
ordinal: 49000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既存の BookmarkStore(App/BookmarkStore.swift、TASK-28 系で実装済み)を再利用し、
CLI から `befold bookmark add <path>` のようなサブコマンドでブックマークを
追加できるようにする。TASK-73.1 の引数パーサー基盤に依存する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 befold bookmark add <path> でファイルまたはフォルダをブックマークに追加できる
- [x] #2 存在しないパスを指定した場合はエラーメッセージを表示して終了する
- [x] #3 追加したブックマークが GUI（File > Bookmarks サブメニュー等）から確認できる
- [x] #4 既にブックマーク済みのパスを再度指定した場合の挙動が明確である（例: 冪等に成功する、または重複エラーを出す）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: 既存の BookmarkStore(App/BookmarkStore.swift、TASK-28系実装済み)に冪等な add(_:) を追加(toggle は反転のため CLI の add 用途には使えず、専用メソッドが必要だった)。CLIBookmarkCommand(新規、App/CLISubcommandCommand.swift)がサブコマンド引数を検証しBookmarkStore.addを呼ぶ純粋寄りの関数として実装(bookmarkStore/fileExistsを注入可能にしテスト容易性を確保)。CLIArgumentParser.subcommandsに'bookmark'を登録。AppDelegate.main()にrunSubcommand(name:arguments:)を追加し、GUIを起動せずstdout/stderrへ結果を出力してexitする(bookmark added→exit(0)、使い方誤り→exit(64)、存在しないパス→exit(1))。ブックマークはUserDefaults永続化のため、GUI側のBookmarksMenuController(既存)がメニュー表示時に毎回bookmarkedURLs()を読み直す既存実装により、CLI追加分もFile>Bookmarksサブメニューから確認できる(AC3)。検証: swift test 512件全パス(BookmarkStoreTests 2件追加、CLIBookmarkCommandTests新規4件、CLIArgumentParserTests 2件追加)、swiftlint新規違反なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
befold bookmark add <path> サブコマンドを実装。既存のBookmarkStoreにadd(_:)を追加して冪等な追加を実現し、CLIBookmarkCommandがGUIを起動せず結果を返す設計にした。追加したブックマークは既存のBookmarksMenuController経由でGUIのFile>Bookmarksから確認できる。存在しないパスや誤った使い方はエラーメッセージ+終了コードで通知する。swift test 512件全パスで検証済み。
<!-- SECTION:FINAL_SUMMARY:END -->
