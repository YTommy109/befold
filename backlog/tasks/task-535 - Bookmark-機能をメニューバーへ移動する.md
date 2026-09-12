---
id: TASK-535
title: Bookmark メニューをトップレベルメニューへ独立させる
status: To Do
assignee: []
created_date: '2026-08-21 07:25'
updated_date: '2026-09-12 11:21'
labels: []
milestone: m-9
dependencies: []
priority: medium
type: enhancement
ordinal: 775000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ブックマークの導線がメインメニューの 2 箇所に分かれている。一覧は File > Bookmarks サブメニュー（`MainMenuBuilder.makeFileMenuItem` の `menu.file.bookmarks`、delegate は `BookmarksMenuController`）、追加/削除トグルは View メニュー（`MainMenuBuilder+ViewMenu.swift` の `menu.view.addBookmark` → `ViewerWindowController.toggleBookmark(_:)`、キー等価は `BookmarkShortcut.keyEquivalent`）にある。

File メニューは Open Recent / Recent Repositories と並ぶ「開く操作と履歴」の場所で、手動で登録するブックマークは性質が違う。ブックマークをトップレベルメニューへ独立させ、追加/削除・一覧・Remove Missing Bookmarks を 1 箇所に集める。

並び位置は View と Window のあいだを想定する（Safari の Bookmarks と同じ位置）。着手時に妥当なら変えてよいが、変えたなら理由を Notes に残すこと。

ツールバーの Bookmark ボタン（`ViewerToolbarController`、SF Symbol `bookmark`/`bookmark.fill`）は本タスクでは廃止しない。ブックマーク済みかどうかを一目で判別する役割は引き続きツールバーが担う。

着手前に知っておくべき波及:
- 新しいメニュー構築を別ファイルへ切り出す場合、ファイル名は `MainMenuBuilder*.swift` を保つこと。`site/vitest.config.ts` の `readMainMenuBuilderSwift` と `.github/workflows/site.yml` の paths が、この glob でメニュー定義を全件拾っている。外れると紹介サイトのショートカット検証が黙って通らなくなる。
- `menu.view.addBookmark` は View メニューだけのキーではない。`ViewerCommandTitles.bookmark(isBookmarked:)`（状態に応じた項目名の切り替え）と `ViewerToolbarController`（ツールバーボタンの labelKey）も同じキーを参照する。キーを改名するならこの 2 箇所も併せて動かす。
- `site/test/shortcuts.test.ts` はキー等価を持つ項目をローカライズキーとソース順で全件突き合わせている。`site/src/views/features.tsx` の ⌘D 行は文言のみ。
- `MenuShortcutCatalogTests` は File グループに Bookmarks サブメニューが現れないことを見ている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 メニューバーに独立した Bookmarks メニューがあり、View と Window のあいだに並ぶ
- [ ] #2 File メニューから Bookmarks サブメニューが無くなっている（Open Recent / Recent Repositories は残る）
- [ ] #3 ブックマークの追加/削除トグルが Bookmarks メニューから行え、既存のキーボードショートカット（⌘D）と、ブックマーク済みかどうかに応じた項目名の切り替えが維持されている
- [ ] #4 ブックマーク済みファイルの一覧表示と Remove Missing Bookmarks が Bookmarks メニューから行える
- [ ] #5 メニュータイトルと項目名が日本語・英語の両方でローカライズされている
- [ ] #6 アプリ内ショートカット一覧（MenuShortcutCatalog）と紹介サイトのショートカット検証（site/test/shortcuts.test.ts）が新しいメニュー構成に追随している
- [ ] #7 ツールバーの Bookmark ボタンは従来どおり動作する（本タスクでは廃止しない）
<!-- AC:END -->
