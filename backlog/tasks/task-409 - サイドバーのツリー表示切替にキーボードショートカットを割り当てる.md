---
id: TASK-409
title: サイドバーのツリー表示切替にキーボードショートカットを割り当てる
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 06:10'
updated_date: '2026-08-13 10:49'
labels: []
dependencies: []
priority: low
type: enhancement
ordinal: 120000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
サイドバーの表示モード（drillDown / tree）の切替が、現在はメニュー項目のみでキーエクイバレントを持たない（App/MainMenuBuilder+ViewMenu.swift:64 `addSidebarTreeLayoutItem`、`FeatureGate.isSidebarTreeEnabled` 配下）。

TASK-408 で整理するとおり、モードによって → / ← の意味が変わる（tree では展開・折りたたみ、drillDown では階層の出入り）。挙動が変わる切替がメニュー専用なのは、キーボード中心の操作では重い。

既存のサイドバー関連ショートカットとの衝突に注意する: cmd+S（サイドバー開閉, :34）、ctrl+cmd+H（隠しファイル, :81）、ctrl+cmd+G（変更のみ, :90）。ctrl+cmd+ 系に揃えるのが既存の並びとは整合する。

FeatureGate 配下のためコミット件名に `(gate)` スコープを付ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 表示モードの切替にキーボードショートカットが割り当てられている
- [x] #2 既存のメニューショートカット（cmd+S / ctrl+cmd+H / ctrl+cmd+G / cmd+[ / cmd+]）と衝突していない
- [x] #3 FeatureGate が OFF のとき、この項目とショートカットがメニューに現れない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. addSidebarTreeLayoutItem に keyEquivalent "t" + [.command, .control] を付与（既存の ⌃⌘H / ⌃⌘G と同じ並び。⌘T・⌃⌘T は未使用で衝突なし）
2. doc コメントの「ショートカットは付けない」を実際の割り当てへ更新
3. MainMenuBuilderTests のツリー表示テストに、ゲート ON でキー等価 ⌃⌘T、OFF で項目なしのアサートを追加
4. site/test/shortcuts.test.ts の EXPECTED_MENU_ITEMS と GATED_LOCALIZATION_KEYS に menu.view.sidebarTreeLayout を追加（ゲート配下なのでサイトには載せない）
5. swift test / site の vitest / swiftlint 差分ゼロを確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
サイドバーのツリー表示切替(menu.view.sidebarTreeLayout)に ⌃⌘T を割り当てた。既存の ⌃⌘H(不可視ファイル) / ⌃⌘G(変更のみ) と同じ ⌃⌘ 系に揃えている。素の ⌘T・⌃⌘T はいずれも未使用(rg で確認)。

検証:
- swift test 1500 tests / 236 suites 全通過
- MainMenuBuilderTests に (a) ゲート ON で keyEquivalent=="t" かつ modifier==[.command,.control]、OFF で項目なし、(b) View メニュー全体でキー等価(キー+修飾キー)が重複しない、の 2 点を追加。(a) は割り当てを外した状態で実際に落ちることを確認済み(MainMenuBuilderTests.swift:174/175 で失敗)
- site/test/shortcuts.test.ts の EXPECTED_MENU_ITEMS に追加し、GATED_LOCALIZATION_KEYS にも入れた(ゲート配下なので紹介サイトには載せない)。vitest 9 tests 通過
- swiftlint: 変更ファイルに新規警告なし
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーのツリー表示切替に ⌃⌘T を割り当て(⌃⌘ 系の既存サイドバー項目に整合)。ゲート ON/OFF 両方向のキー等価アサートと View メニュー内キー等価の重複検査テストを追加、紹介サイト側の突き合わせ表もゲート項目として更新。swift test 1500 件・site vitest 9 件すべて通過。
<!-- SECTION:FINAL_SUMMARY:END -->
