---
id: TASK-913
title: Xcode 27 SDK で ObjC デリゲートのメソッドが呼ばれなくなる同型の問題を洗う
status: To Do
assignee: []
created_date: '2026-11-07T06:38:00Z'
labels:
  - ci
  - objc
  - xcode
dependencies: []
references:
  - BefoldApp/BefoldRenderKit/WebKitSurfaceEventBridge.swift
  - BefoldApp/befold/App/AppDelegate.swift
  - BefoldApp/befold/App/DocumentController.swift
priority: medium
type: bug
ordinal: 879000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
PR #750 の調査で、closure 引数の actor 注釈が SDK の宣言と合わないと、optional なデリゲートメソッドの selector が公開されず、呼ばれなくなることが分かった。実測: Swift 6 モード / SDK 27.2 で decisionHandler に @MainActor が無いと responds(to:) が false（Swift 5 モードでは true）。コンパイラは nearly matches の警告を出すだけでビルドは通る。リリース 1.24.0（SDK 26.5）のバイナリには selector があるので、CI とリリースが Xcode 26.6 の間は表に出ず、Xcode 27 へ上げた時点で黙って動かなくなる。同じ形の候補は AppDelegate の UNUserNotificationCenterDelegate と DocumentController だが、問題があるかは未確認。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Xcode 27 SDK のビルドで nearly matches の警告を一覧にし、すべて解消するか問題が無い理由を記録している
- [ ] #2 closure 引数を持つ ObjC デリゲートの実装それぞれについて、selector が公開されていることを確認している
- [ ] #3 この型の不具合が再発したら CI または自動テストで落ちる仕組みがあるか、置かない理由が記録されている
- [ ] #4 CI とリリースの Xcode を 27 へ上げる前に必要な確認が Notes か該当タスクへ残っている
<!-- AC:END -->
