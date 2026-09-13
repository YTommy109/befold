---
id: TASK-620.4
title: cmd+shift+D で Bookmark Editor を開けるようにする
status: To Do
assignee:
  - '@claude'
created_date: '2026-09-13 11:43'
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
ブックマーク管理パネルを開く手段が Bookmarks > ブックマークを編集… のメニューしか無い。ブックマークの追加/解除が cmd+D（`BookmarkShortcut`）なので、隣の cmd+shift+D で管理パネルを開けるようにしたい。

TASK-536.1 では「ブックマークを編集…」に「キー等価は付けない——付けると紹介サイトのショートカット検証（`site/test/shortcuts.test.ts`）と Help の一覧に載る項目が増える」と判断していた（`MainMenuBuilder.addEditBookmarksItem(to:)` の doc コメントと native-app-design.md の `MainMenuBuilder` の行）。今回はその判断を覆すので、載る項目が増えることを受け入れ、サイト側・Help 側・文書を揃える。

2026-09-13 時点で `MainMenuBuilder*.swift` に cmd+shift+D のキー等価は無い（`keyEquivalent: "d"` は `BookmarkShortcut` の 1 件だけ）。メニュー以外（`.onKeyPress`・ビューア JS）での衝突は着手時に確認する。

キー表記は cmd+D と同じく 1 箇所に置き、メニュー登録と表記がそこから導かれる形を保つこと。メニュー項目の action は `AppDelegate.showBookmarkManager(_:)`（`panels.toggle(.bookmarks)`）なので、2 回押すと閉じる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 cmd+shift+D で管理パネルが開き、もう一度押すと閉じる
- [ ] #2 ビューア窓が 1 枚も無い状態でも cmd+shift+D で開ける
- [ ] #3 Bookmarks メニューの「ブックマークを編集…」にキー表記が出る
- [ ] #4 Help > キーボードショートカット の一覧に載る（MenuShortcutCatalogTests で担保）
- [ ] #5 紹介サイトのショートカット一覧と site/test/shortcuts.test.ts が更新され、テストが通る
- [ ] #6 addEditBookmarksItem の doc コメントと native-app-design.md の「キー等価を付けない」記述が更新されている
<!-- AC:END -->
