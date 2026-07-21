---
id: TASK-77
title: showLineNumbersOverrideがstore明示注入時に無視される
status: Done
assignee: []
created_date: '2026-07-21 00:52'
updated_date: '2026-07-21 01:40'
labels: []
dependencies: []
priority: medium
type: bug
ordinal: 62000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowController.init で store: ViewerStore? パラメータに明示的な store を渡した場合、showLineNumbersOverride が適用されない。self.store = store ?? ViewerStore(defaults: defaults, showLineNumbersOverride: showLineNumbersOverride) は store が nil の場合のみ override を反映するため、store と showLineNumbersOverride を両方渡す呼び出しでは override が黙って無視される(コンパイルエラーにならない)。task-73.13 の修正(swift test 527件通過時点)で導入された回帰。参照: code review finding, BefoldApp/befold/App/ViewerWindowController.swift:108
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 store: と showLineNumbersOverride: を両方指定した場合でも showLineNumbersOverride が反映されること
- [x] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
単純化を検討: sourceModeOverride は既に『store 生成後に post-hoc 適用する』方式で、store 注入有無に関わらず一律に効く設計だった。showLineNumbersOverride だけが ViewerStore.init 引数(store が nil の時のみ有効)という特殊経路になっていたのが根本原因。ViewerStore.init から showLineNumbersOverride 引数を削除し、ViewerStore.applyShowLineNumbersOverride(_:) を新設して sourceModeOverride と同じ post-hoc 適用パターンに統一。永続化抑止は _showLineNumbers 直接代入では didSet を回避できなかった(@Observable マクロ展開で backing storage への代入でも didSet が発火する)ため、suppressShowLineNumbersPersistence フラグでガードする方式に変更。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerWindowController.init の showLineNumbersOverride 適用を、store 生成時(nilの場合のみ)から store 生成後の post-hoc 適用(store.applyShowLineNumbersOverride)へ変更し、store を明示注入した場合でも override が反映されるようにした。既存の sourceModeOverride と同じ適用パターンに統一。回帰テスト(store を明示注入した場合でも --line-numbers 指定が反映される)を追加。swift test --skip Integration --skip FileWatcherTests で528件全てパス(新規テスト含む)。
<!-- SECTION:FINAL_SUMMARY:END -->
