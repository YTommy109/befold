---
id: TASK-170
title: Quick Open パネルの配置がウィンドウ中央よりやや右寄りになる
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-27 11:29'
updated_date: '2026-07-27 12:11'
labels: []
dependencies: []
ordinal: 245000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
QuickOpenPanelController.position(_:) は x = reference.midX - size.width / 2 で水平中央配置を意図しているが、position() 呼び出し時点(panel.layoutIfNeeded() 直後)で SwiftUI コンテンツの preferredContentSize がまだ確定しておらず、size.width が最終サイズより小さい状態で原点を計算している可能性がある。結果としてパネルが本来より左寄りに配置され、その後コンテンツ幅が確定して広がることで見た目上ウィンドウ中央よりやや右寄りに見える。QuickOpenPanelController.swift の position(_:) / present() まわりを調査し、パネルの最終サイズが確定してから x 座標を計算するよう修正する。新しい状態やフラグを追加せず、既存のサイズ確定タイミングを見直すだけで直せないか優先的に検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 Quick Open (Cmd+P) を開いたとき、パネルがキーウィンドウ(またはメイン画面)の水平中央に正しく表示される
- [x] #2 候補リストの内容によってパネル幅が変わっても中央配置がずれない
- [x] #3 既存の垂直方向の配置(verticalPositionRatio)には影響しない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. position() 時点で panel.frame.size が未確定(幅0)であることが原因と特定。x = midX - 0 となり左端が中央に来て『右寄り』に見える。
2. 新しい状態やフラグを追加せず、present() で contentViewController の fittingSize を明示的にパネルへ適用してサイズを確定させてから position() を呼ぶ形に単純化する。
3. QuickOpenView の幅は .frame(width: 640) で固定のため、候補数が変わっても水平位置はずれない。
4. 垂直位置計算(verticalPositionRatio)はそのまま維持。
5. swift build / swift test と実機での目視確認。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実機ログ検証: position() 冒頭 panel.layoutIfNeeded() 直後の panel.frame.width は 0.0 で、x = midX - 0 となりパネル左端がウィンドウ中央に来ていた(=右寄りに見える)。contentViewController.view.fittingSize を setContentSize で適用後は width=640.0(QuickOpenView の .frame(width: 640) と一致)となり、reference.midX=1441.5 に対し x=1121.5 の水平中央配置になることを確認。幅は固定 640 のため候補数が変わっても水平位置はずれない(AC#2)。垂直計算は未変更(AC#3)。swift test 799 tests passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
QuickOpenPanelController.position() で SwiftUI 側の要求サイズをパネルへ確定させてから原点を計算するよう修正。新しい状態は追加していない。実機 NSLog で修正前 width=0.0 → 修正後 640.0、水平中央配置になることを確認。swift test 799 tests passed。
<!-- SECTION:FINAL_SUMMARY:END -->
