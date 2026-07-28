---
id: TASK-176
title: Quick Open 表示中に他アプリへ切り替えるとパネルが残る
status: To Do
assignee: []
created_date: '2026-07-28 00:48'
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
- [ ] #1 Quick Open を開いた状態で他アプリへ切り替えると、パネルが閉じる
- [ ] #2 befold 内の別ウィンドウへフォーカスが移った既存の閉じる挙動(windowDidResignKey)は維持される
- [ ] #3 パネル未表示時にアプリが非アクティブ化しても副作用(クラッシュ・不要な処理)がない
- [ ] #4 アプリ非アクティブ化での閉じ挙動を検証するテストを追加する(自動化可能な範囲で)
<!-- AC:END -->
