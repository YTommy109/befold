---
id: TASK-235
title: NSMenu 構築ヘルパーを抽出しメニューデリゲートと MainMenuBuilder のボイラープレートを削減する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:16'
updated_date: '2026-07-31 22:39'
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
- [x] #1 アイコン付きメニュー項目の生成が共通ヘルパー 1 箇所に集約され、各メニューの表示・動作が従来と同等である
- [x] #2 MainMenuBuilderTests など既存テストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. NSMenu+Items.swift に項目生成ヘルパー(NSMenuItem.action / NSMenu.addActionItem / addFileItem / NSImage.sizedForMenuItem)を抽出
2. Recent Documents / Recent Repositories / Bookmarks / HistoryButtonView の 4 箇所を畳む
3. MainMenuBuilder 向けに addLocalizedItem(modifiers 含む) / addLocalizedSubmenu を追加
4. MainMenuBuilder の addItem 4 行ブロック・keyEquivalentModifierMask 8 箇所・デリゲート付きサブメニュー 3 連コピーを畳む(NSApp.servicesMenu の特殊代入は据え置き)
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
befold/App/NSMenu+Items.swift を新設し、メニュー項目生成のボイラープレートを集約した: NSMenuItem.action(title:action:target:representedObject:image:tag:) / NSMenuItem.icon(forFile:) / NSImage.sizedForMenuItem() / NSMenu.addActionItem / NSMenu.addFileItem。これで RecentDocuments・Bookmarks・RecentRepositories・HistoryButtonView の 4 箇所の同型コード（項目生成 + target/representedObject + 16×16 アイコン）が畳まれ、16pt の指定も 1 箇所になった。ジェネリックデリゲート化は representedObject への struct ブリッジ懸念があるため見送り、課題どおりヘルパー抽出に留めた。余力分として MainMenuBuilder も addLocalizedItem(modifiers:) / addLocalizedSubmenu(delegate:) で削減（384行→263行）: addItem の 4 行ブロック 45 箇所、keyEquivalentModifierMask の後付け代入 8 箇所、デリゲート付きサブメニューの 3 連コピーを撤去。NSApp.servicesMenu の特殊代入は課題の指示どおり巻き込んでいない。検証: swift test → 939 passed(MainMenuBuilderTests 含む) / swiftformat --lint パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
メニュー項目生成のヘルパーを NSMenu+Items.swift へ抽出し、Recent/Bookmarks/履歴メニューの同型コード 4 箇所を集約。あわせて MainMenuBuilder のボイラープレートも同ヘルパーで畳み 384→263 行に削減した。swift test 939 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
