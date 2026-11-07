---
id: TASK-915
title: 空タブでサイドバーの開閉（⌘S・ツールバー）が効くか確かめ、効かなければ直す
status: To Do
assignee: []
created_date: '2026-11-07T08:35:00Z'
labels:
  - sidebar
  - tabs
dependencies: []
references:
  - BefoldApp/befold/App/BlankTabWindowController.swift
  - BefoldApp/befold/App/DocumentFileDropView.swift
priority: high
type: bug
ordinal: 881000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
スタック #769 のレビューで検出。空タブにはフォーカスを取る部品が無いので first responder は窓自身になりうる。`toggleSidebar(_:)` は宛先なしのアクションで、`ViewerSplitViewController` はビューの responder chain 上にある。窓から上へ辿る経路には split view が乗らず、`DocumentFileDropView.install` が contentViewController を素の container に差し替えているので、container 経由の転送にも期待できない。そうなると、サイドバーを閉じた窓から開いた空タブではサイドバーをもう開けない。

未確認（仮説）: コードからの推論で、再現はしていない。TASK-910 の Notes にも実機未確認とある。既存テストは `toggleSidebar` を直接呼ぶので、この経路を測っていない。確認方法: `/run` で閉じたサイドバーの窓から ⌘T を押し、⌘S とツールバーのボタンを試す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 実機で空タブの ⌘S とツールバーのボタンを試した結果が Notes に記録されている
- [ ] #2 サイドバーを閉じた窓から開いた空タブで、⌘S とツールバーのボタンからサイドバーを開閉できる
- [ ] #3 開閉が利用者の操作として保存値へ記録される
<!-- AC:END -->
