---
id: TASK-308
title: 「最近使った項目」「ブックマーク」メニューにパスを併記する（ファイル名左寄せ・パス右寄せ）
status: Done
assignee:
  - '@claude'
created_date: '2026-08-05 02:00'
updated_date: '2026-08-05 05:59'
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
- [x] #1 「最近使った項目」メニューの各行に、ファイル名(左寄せ)とパス(右寄せ)が同じ行に表示される
- [x] #2 「ブックマーク」メニューの各行にも同様にファイル名とパスが表示される
- [x] #3 パスが長い場合でも省略等でメニュー行の見た目が破綻しない
- [x] #4 両メニューが表示ロジックを共有し、重複実装にならない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. NSMenu+Items.swift に FileMenuTitleLayout（ファイル名+右寄せパスの attributedTitle 生成）と addFileItems(urls:action:target:) を追加する
2. RecentDocumentsMenuController / BookmarksMenuController を addFileItems へ寄せる
3. 単体テスト（2列化・~ 省略・長いパスの先頭省略・タブストップ共有）と既存テストの期待値更新
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: メニュー1枚分の URL をまとめて渡し、名前幅+パス幅の実測最大値からタブストップ位置を決めて右寄せ列を作る。パスは親ディレクトリのみ、ホーム配下は ~ に畳み、320pt を超える場合は先頭を …/ に畳む。attributedTitle を設定すると NSMenuItem.title も 'name\tpath' になるため既存テストの期待値を更新した。
検証: swift test 全 1033 件 pass。見た目は使い捨ての描画プローブで PNG に出して確認し、3 行とも drawnWidth == tabStop（423.18pt）で右端が揃い、深いパスが …/ 省略で 320pt 以内に収まることを実測（プローブは確認後に削除）。swiftlint は変更ファイルで警告 0 件、swiftformat --lint も差分なし。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
NSMenu+Items.swift に FileMenuTitleLayout と addFileItems(urls:action:target:) を追加し、Recent Documents と Bookmarks の両メニューをそこへ寄せた。各行はファイル名（左）と親ディレクトリのパス（右寄せ・小さめの二次色）の2列で、列位置はメニュー1枚分の実測幅から決まる。ホーム配下は ~ に畳み、320pt を超えるパスは先頭を …/ に省略する。swift test 1033 件 pass、描画プローブで右端の揃い（drawnWidth == tabStop）と長いパスの省略を実測して確認。
<!-- SECTION:FINAL_SUMMARY:END -->
