---
id: TASK-308
title: 「最近使った項目」「ブックマーク」メニューにパスを併記する（ファイル名左寄せ・パス右寄せ）
status: To Do
assignee: []
created_date: '2026-08-05 02:00'
labels: []
dependencies: []
priority: medium
ordinal: 506000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 RecentDocumentsMenuController.swift:26 と BookmarksMenuController.swift:20 はどちらも NSMenu+Items.swift の addFileItem(title:filePath:...) を通じてメニュー項目を組み立てており、表示タイトルは url.lastPathComponent のみで、filePath はメニューアイコン取得(NSMenuItem.icon(forFile:))にしか使われていない。同名ファイルが別フォルダーに複数ある場合、メニュー上でどれがどれか区別できない。Xcode の Open Recent のように、各行にファイル名を左寄せ、フルパス(または親ディレクトリのパス)を右寄せで併記し、一覧性を上げたい。両メニューは同じ addFileItem を共有しているため、表示ロジックはそこに集約する想定(重複実装を避ける)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 「最近使った項目」メニューの各行に、ファイル名(左寄せ)とパス(右寄せ)が同じ行に表示される
- [ ] #2 「ブックマーク」メニューの各行にも同様にファイル名とパスが表示される
- [ ] #3 パスが長い場合でも省略等でメニュー行の見た目が破綻しない
- [ ] #4 両メニューが表示ロジックを共有し、重複実装にならない
<!-- AC:END -->
