---
id: TASK-620.4
title: cmd+shift+D で Bookmark Editor を開けるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-09-13 11:43'
updated_date: '2026-09-13 15:11'
labels: []
milestone: m-9
dependencies: []
parent_task_id: TASK-620
priority: medium
type: feature
ordinal: 814000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Bookmark Editor を開く手段が Bookmarks > ブックマークを編集… のメニューしか無い。ブックマークの追加/解除が cmd+D（`BookmarkShortcut`）なので、隣の cmd+shift+D で Bookmark Editor を開けるようにしたい。

TASK-536.1 では「ブックマークを編集…」に「キー等価は付けない——付けると紹介サイトのショートカット検証（`site/test/shortcuts.test.ts`）と Help の一覧に載る項目が増える」と判断していた（`MainMenuBuilder.addEditBookmarksItem(to:)` の doc コメントと native-app-design.md の `MainMenuBuilder` の行）。今回はその判断を覆すので、載る項目が増えることを受け入れ、サイト側・Help 側・文書を揃える。

2026-09-13 時点で `MainMenuBuilder*.swift` に cmd+shift+D のキー等価は無い（`keyEquivalent: "d"` は `BookmarkShortcut` の 1 件だけ）。メニュー以外（`.onKeyPress`・ビューア JS）での衝突は着手時に確認する。

キー表記は cmd+D と同じく 1 箇所に置き、メニュー登録と表記がそこから導かれる形を保つこと。メニュー項目の action は `AppDelegate.showBookmarkManager(_:)`（`panels.toggle(.bookmarks)`）なので、2 回押すと閉じる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 cmd+shift+D で Bookmark Editor が開き、もう一度押すと閉じる
- [x] #2 ビューア窓が 1 枚も無い状態でも cmd+shift+D で開ける
- [x] #3 Bookmarks メニューの「ブックマークを編集…」にキー表記が出る
- [x] #4 Help > キーボードショートカット の一覧に載る（MenuShortcutCatalogTests で担保）
- [x] #5 紹介サイトのショートカット一覧と site/test/shortcuts.test.ts が更新され、テストが通る
- [x] #6 addEditBookmarksItem の doc コメントと native-app-design.md の「キー等価を付けない」記述が更新されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. MainMenuBuilder.addEditBookmarksItem に BookmarkShortcut.keyEquivalent + [.command, .shift] を付ける（キー文字は cmd+D と同じ定数から導く）
2. MenuShortcutCatalogTests に ⇧⌘D のケースを足す
3. site の SHORTCUTS と shortcuts.test.ts の EXPECTED_MENU_ITEMS に足す
4. doc コメントと native-app-design.md の「キー等価を付けない」記述を改める
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 修飾キーはメニュー定義の行に書き、キー文字だけ BookmarkShortcut.keyEquivalent を共有した（サイトのパーサーは modifiers をリテラルでしか読めないため、修飾キーまで定数に寄せると検証が効かなくなる）。表記用の定数（editor 用 displayName）は読み手が無いので足していない。
衝突確認: MainMenuBuilder*.swift に cmd+shift+D は無し。viewer-src に d キーの処理は無し。viewer-diff.test.js のコメントにある ⇧⌘D は旧・左右分割の名残で、現行の割り当ては ⌘\。
検証:
- swift test --skip Integration --skip FileWatcherTests: 1930 件パス
- メニュー定義を HEAD へ戻すと MenuShortcutCatalogTests.modifierSymbolsFollowStandardOrder の ⇧⌘D ケースが落ちる（Expectation failed: entries(inGroupTitled:)）
- site: npx vitest run test/shortcuts.test.ts 9 件パス
- swiftlint: origin/main との差分ゼロ（48 → 48）
- 実機（xcodebuild Debug、System Events で操作）: ⇧⌘D で窓一覧が [CLAUDE.md] → [Bookmarks, CLAUDE.md] → [CLAUDE.md]。cmd+W で窓を 0 枚にしても [] → [Bookmarks] → []。Bookmarks メニューの Edit Bookmarks… は AXMenuItemCmdChar=D / AXMenuItemCmdModifiers=1（⇧⌘）
native-app-design.md: MainMenuBuilder の行を更新した

型グループ MainMenuBuilder が 456 行となり恒久例外の上限 449 を超えた（コミット時フックで検知）。doc コメントを 1 行へ畳み（経緯は native-app-design.md に置いた）451 行まで削り、残る +2（キー等価と修飾キーの引数）は TASK-536.1 の前例どおり scripts/type-group-exceptions.txt の上限を実測値 451 へ合わせ、理由を追記した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
「ブックマークを編集…」に ⇧⌘D を割り当てた（キー文字は BookmarkShortcut.keyEquivalent を共有）。Help 一覧・紹介サイトの表と検証テスト・doc コメント・native-app-design.md を揃えた。Swift 1930 件 / site shortcuts 9 件パス、実機で開閉と窓 0 枚での起動を確認。
<!-- SECTION:FINAL_SUMMARY:END -->
