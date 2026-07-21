---
id: TASK-73.13
title: CLI の行番号表示オプション指定が保存済み設定を永続的に上書きする
status: Done
assignee:
  - '@claude'
created_date: '2026-07-20 13:30'
updated_date: '2026-07-21 00:32'
labels: []
dependencies: []
references:
  - 'code review finding: BefoldApp/befold/App/ViewerWindowController.swift:110'
  - 'BefoldApp/befold/Viewer/ViewerStore.swift:118-122'
parent_task_id: TASK-73
priority: medium
type: bug
ordinal: 60000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ViewerWindowController 初期化時、CLI の --line-numbers/--no-line-numbers オーバーライドは store.showLineNumbers に直接代入している。ViewerStore.showLineNumbers には didSet で UserDefaults へ書き込む副作用があるため、1回のCLI起動時オーバーライドがユーザーの保存済みグローバル設定を恒久的に上書きしてしまう。隣接する --source/--preview のオーバーライド(sourceModeOverride)は明示的に保存値を書き換えない実装になっており、意図とも矛盾している。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 CLIからの --line-numbers/--no-line-numbers 指定は、その起動セッション限りの表示に反映され、UserDefaultsに保存されたグローバル設定を書き換えないこと
- [x] #2 回帰テストを追加する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
ViewerStore.initにshowLineNumbersOverride: Bool?を追加し、_showLineNumbers(バッキングストレージ)へ直接代入することでdidSetのUserDefaults書き込みを経由させない。ViewerWindowController.initのstoreパラメータをOptionalにし、未指定時はViewerStore(defaults:showLineNumbersOverride:)で生成することでオーバーライドをコンストラクタ経由にする(既存のsourceModeOverride/isSourceModeパターンと同じ、保存値と表示中の値を分離する設計)。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
ViewerStore.init(...)にshowLineNumbersOverride: Bool? = nilを追加し、_showLineNumbers = showLineNumbersOverride ?? defaults.bool(forKey:)としてバッキングストレージへ直接設定(didSetのUserDefaults書き込みを経由しない)。ViewerWindowController.initのstoreパラメータをViewerStore? = nilに変更し、self.store = store ?? ViewerStore(defaults: defaults, showLineNumbersOverride: showLineNumbersOverride)とすることで、従来の『生成後にstore.showLineNumbers = overrideを代入』(didSet発火→永続化)というバグの原因だったパターンを排除した。--source/--previewのsourceModeOverride(perFileState.sourceMode書き換えなしの設計)と同じ『保存値と表示中の値を分離する』考え方を踏襲。ViewerWindowControllerCLIOptionsTests.swiftに、オーバーライド指定時にUserDefaultsの保存値が変化しないことを検証するテストと、未指定時に保存値がそのまま復元されることを検証するテストを追加。swift test 527件全パス。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerStore.initにshowLineNumbersOverrideを追加し、CLIの--line-numbers/--no-line-numbers指定をバッキングストレージへ直接設定するようにした。従来のstore.showLineNumbers=override代入がdidSetのUserDefaults書き込みを誘発し保存済みグローバル設定を恒久上書きしていた問題を解消し、--source/--previewと同様にこの起動限りの上書きに留めた。
<!-- SECTION:FINAL_SUMMARY:END -->
