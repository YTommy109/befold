---
id: TASK-75
title: CLI から開いたファイルのウィンドウがアクティブにならない可能性の調査
status: To Do
assignee: []
created_date: '2026-07-19 11:54'
labels: []
dependencies: []
ordinal: 52000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
既に他のウィンドウが開いている状態で CLI（`open -a befold <file>` 経由の
シム、AppDelegate.application(_:open:) → ViewerWindowManager.openViewer）から
新しいファイルを開いたとき、指定したファイルのウィンドウが必ずしも
アクティブ（キーウィンドウ・最前面）にならない可能性がある。原因調査を行う。

関連コード:
- App/AppDelegate.swift: application(_:open:)（複数 URL を受け取る経路）
- App/ViewerWindowManager.swift: openViewer(for:forceSidebarVisible:)
  （新規ウィンドウは showWindow(nil) 後に NSApp.activate() を呼んでいるが、
  複数ファイル同時オープン時やアプリが既にアクティブな場合の前面化タイミングは
  未検証。既存ファイルの場合は makeKeyAndOrderFront を呼んでいる）

TASK-73（CLI オプション拡充）で複数ファイル/フォルダを複数ウィンドウで開く
機能を実装する際にも影響しうるため、先行して原因を切り分ける。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 既存ウィンドウがある状態で CLI から1ファイルを開いたとき、対象ウィンドウがアクティブになるかどうかの再現条件を明確化する
- [ ] #2 複数ファイルを同時に CLI から開いた場合に、どのウィンドウがアクティブになるか（あるいはならないか）を明確化する
- [ ] #3 他アプリがアクティブな状態から CLI 経由で開いた場合と、befold 自体が既にアクティブな状態から開いた場合の挙動差を明確化する
- [ ] #4 原因（NSApp.activate() のタイミング、非同期ウィンドウ生成、Space をまたぐ場合の挙動など）を切り分けて記録する
- [ ] #5 調査結果を踏まえた対応方針（修正が必要か、TASK-73 側で扱うべきか等）を記録する
<!-- AC:END -->
