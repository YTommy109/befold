---
id: TASK-194
title: 'cmd+, (設定ウィンドウ) がトグルにならず閉じられない'
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-29 14:50'
updated_date: '2026-07-29 15:02'
labels: []
dependencies: []
references:
  - BefoldApp/befold/App/AppDelegate.swift
  - BefoldApp/befold/App/CodeFontSettingsWindowController.swift
  - BefoldApp/befold/App/QuickOpenPanelController.swift
  - BefoldApp/befold/App/MainMenuBuilder.swift
priority: medium
type: bug
ordinal: 277000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
showSettings(_:) は既存ウィンドウがあれば前面化するだけで、既に最前面かどうかを見て閉じる処理がない。QuickOpenPanelController.toggle() のようなトグル実装を参考に、cmd+, で開いている設定ウィンドウを閉じられるようにする。バージョン1.10.1-dev.1 (837) で確認。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 設定ウィンドウが開いていて最前面のときに cmd+, を押すとウィンドウが閉じる
- [x] #2 設定ウィンドウが閉じている、または最前面でないときに cmd+, を押すと開く/前面化する
- [x] #3 AppDelegate.showSettings(_:) (BefoldApp/befold/App/AppDelegate.swift) にトグル動作のテストが追加されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CodeFontSettingsWindowController に toggle() を追加(QuickOpenPanelController.toggle() 相当): window が nil または isKeyWindow==false なら showAndActivate、isKeyWindow==true なら window.close()。新規の状態フラグは持たず window.isKeyWindow を単一の判定源にする(単純化: 既存の window 状態を再利用し、専用フラグを増やさない)。
2. AppDelegate.showSettings(_:) を controller.toggle() を呼ぶだけに変更。
3. CodeFontSettingsWindowControllerTests(新規)で toggle() の3ケースをテスト: 未表示から toggle→表示、表示・最前面から toggle→閉じる、表示・非最前面(makeKeyAndOrderFront で他ウィンドウを前面化した状態)から toggle→前面化(閉じない)。
4. swift build / swift test で確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
CodeFontSettingsWindowController に toggle()/isFrontmost シームを追加。showSettings(_:) は controller.toggle() を呼ぶだけに変更。isKeyWindow はこの実行環境の swift test では常に false のままになる(RunLoop を回しても変化しないことを手元スクリプトで確認済み)ため、テストは isFrontmost を注入して判定分岐を検証。swift build / swift test (--skip Integration --skip FileWatcherTests) 全784件成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
showSettings(_:) を CodeFontSettingsWindowController.toggle() に委譲し、最前面なら閉じる/そうでなければ開く・前面化するトグル動作にした。isKeyWindow をテストから注入できる isFrontmost シームで置き換え可能にし、CodeFontSettingsWindowControllerTests(3件)で開閉/前面化の各分岐を検証。swift build 成功、swift test --skip Integration --skip FileWatcherTests は784件全成功。
<!-- SECTION:FINAL_SUMMARY:END -->
