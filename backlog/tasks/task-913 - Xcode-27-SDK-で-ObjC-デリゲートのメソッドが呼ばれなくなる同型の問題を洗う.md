---
id: TASK-913
title: Xcode 27 SDK で ObjC デリゲートのメソッドが呼ばれなくなる同型の問題を洗う
status: Done
assignee:
  - '@claude'
created_date: '2026-11-07T06:38:00Z'
updated_date: '2026-11-07T08:12:00Z'
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
- [x] #1 Xcode 27 SDK のビルドで nearly matches の警告を一覧にし、すべて解消するか問題が無い理由を記録している
- [x] #2 closure 引数を持つ ObjC デリゲートの実装それぞれについて、selector が公開されていることを確認している
- [x] #3 この型の不具合が再発したら CI または自動テストで落ちる仕組みがあるか、置かない理由が記録されている
- [x] #4 CI とリリースの Xcode を 27 へ上げる前に必要な確認が Notes か該当タスクへ残っている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
監査（2026-11-07、Xcode 27.2 / Swift 6.4.2）: swift build --build-tests のクリーンビルドと xcodebuild clean build（QuickLook を含む）で nearly matches は 0 件。TASK-908 の PR で decisionHandler を直した後の状態で、他に同型は無い。
closure 引数の実装: UNUserNotificationCenterDelegate.willPresent は optional なので ObjCDelegateWitnessTests で公開を確認。DocumentController.openDocument は override なのでずれるとビルドが落ちる。QLPreviewingController の async と WKScriptMessageHandler は required で、ずれるとビルドが落ちる。
再発防止: ObjCDelegateWitnessTests は SDK に関係なく公開の事実を測るので CI で落ちる。nearly matches の CI 検査は置かない。CI の Xcode 26.6 では警告が出ず検出できないため。
Xcode 27 へ上げるときの確認: (1) ビルドログを grep して nearly matches が 0 件であること、(2) ObjCDelegateWitnessTests と WebKitSurfaceEventBridgeMappingTests が成功すること、(3) 実機で直接 HTML のリンクの分類と Reload を確認すること（CI の 26.6 と手元の 27.2 で SDK の宣言が違う）。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Xcode 27 SDK のクリーンビルドで nearly matches が 0 件であることを確認し、optional なデリゲートの selector 公開を測る ObjCDelegateWitnessTests を追加した。Xcode を上げるときの確認事項は Notes に残した。
<!-- SECTION:FINAL_SUMMARY:END -->
