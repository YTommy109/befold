---
id: TASK-168
title: Quick Open パネル上部にタイトルバーのセパレータ横線(グレー)が残る
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 09:00'
updated_date: '2026-07-27 10:00'
labels:
  - quick-open
  - bug
  - ui
dependencies: []
priority: medium
type: bug
ordinal: 243000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
Cmd+P で開く Quick Open パネルの上端に、グレーの横線(枠線のような線)が表示される。パネルは styleMask に .titled を含み titleVisibility=.hidden / titlebarAppearsTransparent=true / .fullSizeContentView を設定しているが、macOS のタイトルバー『セパレータ線』が既定で描画されるため残る。

## 原因
NSWindow.titlebarSeparatorStyle の既定(.automatic)がツールバー無しでも境界線を描くことがある。

## 対応方針
QuickOpenPanelController.present() の NSPanel 生成後に panel.titlebarSeparatorStyle = .none を設定して線を消す。

## 該当
BefoldApp/befold/App/QuickOpenPanelController.swift:59-76
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Cmd+P パネル上端のグレーの横線が表示されない(手動確認)
- [x] #2 panel.titlebarSeparatorStyle = .none が設定され、他のパネル挙動(角丸・影・移動)に影響しない
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
原因は titlebarSeparatorStyle=.none では消えない .titled パネルのタイトルバー境界だった。パネルを borderless([.borderless,.nonactivatingPanel])化して解消。素の borderless は canBecomeKey=false で検索フィールドにフォーカスが移らないため、canBecomeKey を true に上書きした KeyableBorderlessPanel サブクラスを導入。実機確認: 上端のグレー横線が消え、Cmd+P 後に focusedUIElement=AXTextField(検索フィールドにフォーカス)で入力可能。全736テスト+lint通過。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Quick Open パネル上部のグレー横線(.titled のタイトルバー境界)を、パネルの borderless 化で解消。フォーカスを保つため canBecomeKey を true にした KeyableBorderlessPanel を導入。実機で線の消失とフィールドフォーカスを確認。
<!-- SECTION:FINAL_SUMMARY:END -->
