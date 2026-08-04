---
id: TASK-89
title: AppDelegate.launch()が引数なしbefold起動でも常にforward()を呼び、不要なACK待ちコストを払う
status: Done
assignee:
  - '@claude'
created_date: '2026-07-21 07:22'
updated_date: '2026-07-21 08:40'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/AppDelegate.swift
priority: low
type: chore
ordinal: 74000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
AppDelegate.launch() は paths が空かつ CLIOpenOptions も未指定の場合(単なる `befold` 起動でウィンドウを前面化したいだけのケース)でも、無条件に CLIInstanceRouter.forward() を呼び出す。
forward() はリクエスト転送とACK待ち(最大1.5秒、TASK-88参照)のコストを伴うため、既存インスタンスをただ activate() するだけで済むはずのケースでも同じコストを払っている。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 pathsが空かつCLIOpenOptionsが全て未指定の場合、forward()のACK待ちコストを経由せず既存インスタンスをactivate()できる
- [x] #2 既存の複数ウィンドウ/表示オプション転送に関する挙動(TASK-73.x/TASK-82等)に回帰がないことをテストで確認する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CLIOpenOptionsはEquatableなので、options == CLIOpenOptions()でパス・表示オプションいずれも未指定かを既存の値だけで判定できる(新しい状態は追加しない)。
2. AppDelegateに純粋関数 isTrivialActivateOnly(paths:options:) を追加し、launch()でrunning instanceがありこの条件を満たす場合はforward()を呼ばずrunning.activate()して即exit(0)する。decideLaunchAction本体・既存分岐は変更しない(TASK-73.x/82等の回帰を避ける)。
3. isTrivialActivateOnlyの単体テストと、既存AppDelegateLaunchTestsのdecideLaunchActionテストが引き続きgreenであることを確認する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装: AppDelegate.isTrivialActivateOnly(paths:options:)を追加(CLIOpenOptionsのEquatable性を利用、新規状態は追加せず単純化)。launch()でrunning instanceがあり単純ケースならforward()をスキップしてactivate()+exit(0)する分岐を追加。検証: swift testで562件全green(新規3件+既存559件、TASK-73.x/82関連の回帰なし)。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
AppDelegate.launch()に、paths/表示オプションいずれも未指定の単純な起動を判定する純粋関数isTrivialActivateOnly()を追加し、この場合はforward()のACK待ちコスト(TASK-88)を経由せず既存インスタンスをrunning.activate()で直接前面化してexit(0)するようにした。decideLaunchAction本体は変更していないため、TASK-73.x/82等の既存分岐・挙動に影響しない。isTrivialActivateOnlyの単体テスト3件を追加し、swift testで562件全green。
<!-- SECTION:FINAL_SUMMARY:END -->
