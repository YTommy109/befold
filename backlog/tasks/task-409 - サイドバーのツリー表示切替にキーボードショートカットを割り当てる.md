---
id: TASK-409
title: サイドバーのツリー表示切替にキーボードショートカットを割り当てる
status: To Do
assignee: []
created_date: '2026-08-10 06:10'
labels: []
dependencies: []
priority: low
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
- [ ] #1 表示モードの切替にキーボードショートカットが割り当てられている
- [ ] #2 既存のメニューショートカット（cmd+S / ctrl+cmd+H / ctrl+cmd+G / cmd+[ / cmd+]）と衝突していない
- [ ] #3 FeatureGate が OFF のとき、この項目とショートカットがメニューに現れない
<!-- AC:END -->
