---
id: TASK-371
title: 同一ファイルを複数ウィンドウで開いた際の表示モード（diff）を同期する
status: To Do
assignee: []
created_date: '2026-08-08 11:22'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/ViewerWindowController.swift
  - BefoldApp/befold/App/ViewerWindowManager.swift
priority: medium
type: bug
ordinal: 512000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
feat/preview_mode の /code-review (high) 指摘。FeatureGate 配下（diff 表示）。TASK-330 で導入した toggleSourceDiff / viewerWindowDidToggleSourceDiff の全ウィンドウ broadcast（ViewerWindowManager が allControllers.forEach { refreshDiff() }）が削除され、「同一ファイルを開いた 2 窓は同じ diff の答えを示す」という不変条件（削除された DiffDisplayPreference の doc コメントが明記していた）を置き換える同一ファイル間の同期処理が無い。setDisplayMode はパス単位で永続化するだけで他窓へ通知しない。新テストは別ファイルを開いた窓のケースしか検証していない。

再現: ファイル X を 2 窓で表示 → 窓 A で diff モード選択 → 窓 B は plain source のままで cmd+3 メニューのチェックも変わらない。再起動後は last-write-wins で両窓とも diff になり、終了前の窓 B の画面と復元状態が食い違う。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 同一ファイルを表示している全ウィンドウに表示モード変更が反映される
- [ ] #2 別ファイルを表示しているウィンドウは影響を受けない
- [ ] #3 同一ファイルを 2 窓で開いたケースをユニットテストで担保する
<!-- AC:END -->
