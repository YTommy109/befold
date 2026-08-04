---
id: TASK-176
title: Quick Open 表示中に他アプリへ切り替えるとパネルが残る
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 00:48'
updated_date: '2026-07-28 02:01'
labels:
  - ui
  - quick-open
dependencies: []
priority: medium
type: bug
ordinal: 251000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Quick Open パネルを開いたまま別アプリケーションへ切り替えると、パネルが画面に残り続ける。QuickOpenPanelController は windowDidResignKey で dismiss() するが、パネルは .nonactivatingPanel + isFloatingPanel=true + level=.floating のフローティングパネルであり、アプリ非アクティブ化をまたいで表示が残るため、他アプリ切替時に閉じない。befold がインアクティブになったら Quick Open を閉じるようにする(Spotlight と同様の振る舞い)。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Quick Open を開いた状態で他アプリへ切り替えると、パネルが閉じる
- [x] #2 befold 内の別ウィンドウへフォーカスが移った既存の閉じる挙動(windowDidResignKey)は維持される
- [x] #3 パネル未表示時にアプリが非アクティブ化しても副作用(クラッシュ・不要な処理)がない
- [x] #4 アプリ非アクティブ化での閉じ挙動を検証するテストを追加する(自動化可能な範囲で)
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. QuickOpenPanelController に NotificationCenter を DI(既定 .default)。
2. present() 中だけ NSApplication.didResignActiveNotification を購読し、発火で dismiss()。dismiss() で購読解除。既存 windowDidResignKey は温存(AC#2)。
3. 未表示時は購読しないため非アクティブ化しても副作用なし(AC#3)。
4. テスト容易化のため isPresented を公開。
5. QuickOpenPanelControllerTests を新設: present→resignActive 通知注入で isPresented=false(AC#1/#4)、未表示時に通知しても no-op・非クラッシュ(AC#3)。既存 StubEnvironment 相当の最小環境を用意。
6. swift test 全緑を確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: swift test 全 814 テスト緑。新設 QuickOpenPanelControllerTests 4件:
- dismissesWhenAppResignsActive: 実際に present() してから NSApplication.didResignActiveNotification を注入 center へポスト → isPresented=false(AC#1)。
- resignActiveWhileNotPresentedIsNoop: 未表示で通知しても非クラッシュ・isPresented=false(AC#3)。
- unsubscribesAfterDismiss: dismiss 後の再ポストで副作用なし(AC#3)。
- doesNotPresentWhenEnvironmentIsNil: 環境 nil ではパネルを開かない。
実装: QuickOpenPanelController に NotificationCenter を DI(既定 .default)。present() 中だけ didResignActiveNotification を selector 購読し handleAppDidResignActive→dismiss()。dismiss() で必ず removeObserver。既存 windowDidResignKey(アプリ内別ウィンドウへのフォーカス移動で閉じる)は温存(AC#2)。テスト観測用に isPresented を公開。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Quick Open パネルが他アプリ切替で閉じ残る問題を修正。.nonactivatingPanel のため windowDidResignKey だけでは他アプリ切替時に閉じないので、present 中だけ NSApplication.didResignActiveNotification を購読して dismiss し、dismiss で購読解除する最小追加で対応。既存の windowDidResignKey 挙動は温存、未表示時は購読しないため副作用なし。NotificationCenter を DI し isPresented を公開して QuickOpenPanelControllerTests を新設、通知注入で閉じ挙動を自動検証。swift test 814 件緑。
<!-- SECTION:FINAL_SUMMARY:END -->
