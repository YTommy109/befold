---
id: TASK-920
title: サイドバーの split view の組み立てを文書タブと空タブで共有する
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T08:35:00Z'
updated_date: '2026-11-07T11:19:00Z'
labels:
  - refactor
  - sidebar
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
  - BefoldApp/befold/App/ViewerWindowAssembler.swift
priority: low
type: task
ordinal: 886000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。`BlankTabWindowController.makeContent` は `ViewerWindowAssembler.makeSplitViewController` の配線（`onCollapsedChange` と `tableFocuser` の 2 つのコールバック）を書き写している。TASK-910 の Notes は「組み立ての重複（split view の配線）は Low のため残した」と記録しているが、.claude/CLAUDE.md の完了基準は「タスク中に発見したリファクタリング課題は「次回触るときに」と後回しにせず、同じタスク内で完了する」と定めている。片方だけを直すと、開閉の記録やフォーカスの後始末（TASK-563）が空タブだけずれる。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 開閉の記録とフォーカスの配線の定義が 1 箇所になっている
- [x] #2 文書タブ・空タブ・スライド窓の開閉の動作が変わらず、既存のテストが通る
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
方針: 開閉の記録と表へのフォーカスの配線を ViewerWindowAssembler.makeSidebarSplit の 1 箇所にし、文書タブと空タブがそれを呼ぶ。担保として ViewerSplitViewController.init の 3 つのコールバックを既定値なしにし、組み立て関数そのものを測るテストを追加した（記録を外すと落ちる）。
code-review high の指摘 6 件: 担保とテストの欠け、allowsSidebar の直書き、キャプチャの前提を直した。モデルと delegate の取り違え、sidebarCollapsible の代入が呼び出し側に残る点は、現在の呼び出し元 2 つで食い違う経路が無いので残した。
実測: swift test 1993 件 + PDF 103 件成功、xcodebuild 成功、swiftlint 新規 0 件。

TASK-915 の層の code-review high で、追加したテストの欠陥 4 件が出たので直した: 時間制限が無く壊れると固まる、開いたときのフォーカス要求を実際には測っていない、開閉の初期状態が autosave に依存する、判定の待ち方。初期状態は setSidebarCollapsed で固定し、待つのはキュー 1 回分だけにした。実測: 開く側・畳む側の配線を外すと、それぞれ即座に落ちる。focusPending は表示していない窓で first responder が成立しないため、読み取り専用で公開したまま（doc に理由を記載）。ViewerSplitViewController.init を呼び出し元から隠す案は、Swift のアクセス制御で同じ型の外へ閉じられないので見送った。

lint の比較手順が重複行を 1 行に畳んでいたため、makeSidebarSplit の引数 6 個の警告（function_parameter_count）を見逃していた。組み立て済みの FileListView を受ける形にして 5 引数へ減らした。モデルと受け手を取り違えられる、というレビュー指摘も同時に解消した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
サイドバーの split view の組み立てを ViewerWindowAssembler.makeSidebarSplit へ集約し、文書タブと空タブで共有した。コールバックを必須引数にし、組み立てを直接測るテストを追加した。動作の変更は無い。
<!-- SECTION:FINAL_SUMMARY:END -->
