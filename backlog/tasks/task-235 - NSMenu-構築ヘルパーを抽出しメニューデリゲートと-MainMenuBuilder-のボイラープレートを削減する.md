---
id: TASK-235
title: NSMenu 構築ヘルパーを抽出しメニューデリゲートと MainMenuBuilder のボイラープレートを削減する
status: To Do
assignee: []
created_date: '2026-07-31 09:16'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 420000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
RecentDocumentsMenuController / RecentRepositoriesMenuController / BookmarksMenuController の menuNeedsUpdate が「removeAllItems → NSMenuItem 生成 + target/representedObject/16×16 アイコン設定 → addItem」の同型コード（Recent 2 つは Clear 項目まで同一）。HistoryButtonView.swift:79-92 にも同型あり。NSMenu 拡張のヘルパー（addFileItem 等）を抽出して 4 箇所を畳む。ジェネリックデリゲート化は representedObject への struct ブリッジの懸念があるためヘルパー抽出に留めるのが安全。余力があれば MainMenuBuilder.swift の addItem 4 行ブロック約 30 回・デリゲート付きサブメニュー 3 連コピーも同ヘルパー（addItem(localized:action:keyEquivalent:modifiers:) / addSubmenu(localized:delegate:)）で削減する（NSApp.servicesMenu 等の特殊代入は巻き込まない）。TASK-204/TASK-228 と同じファイルを触るため実施順に注意。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 アイコン付きメニュー項目の生成が共通ヘルパー 1 箇所に集約され、各メニューの表示・動作が従来と同等である
- [ ] #2 MainMenuBuilderTests など既存テストが通る
<!-- AC:END -->
