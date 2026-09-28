---
id: TASK-657
title: パネル窓の配置方針に本番で効かない分岐と重複した状態が残っている（TASK-656 のレビュー指摘）
status: Done
assignee:
  - '@claude'
created_date: '2026-09-28 06:29'
updated_date: '2026-09-28 06:50'
labels:
  - refactor
dependencies: []
priority: medium
type: chore
ordinal: 857000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-656 の実装後レビュー（/code-review high）の指摘をまとめたもの。原因はいずれも、配置方針の型を実際の窓の性質を確かめずに設計したこと。

## 指摘
1. `HostedPanelPlacement.rememberPosition` の「位置だけ戻す」処理が本番で何もしていない。唯一の利用者である設定窓は `resizable: false` で、AppKit の `setFrameUsingName(_:)` はリサイズ不可の窓では保存値の左上だけを戻しサイズを保つ。レビューの実測では、保存値 `40 0 610 450` のリサイズ不可の窓が (40, 218, 300, 232) に戻った。`restoreFrame` のサイズ戻しは、リサイズ可能な窓でしか効かない。
2. `rememberPositionRestoresOnlyTopLeft` はリサイズ可能な窓で試しており、設定窓が実際に通る経路（リサイズ不可・contentSize nil）を覆っていない。TASK-656 の AC6 はこのテストを根拠に済みにしたので、実質未検証。
3. `makeSimplePanel` に `resizable: Bool = true` の既定値を置いた。変更前は全パネルが明示しており、「既定値を置かない」規約（.claude/CLAUDE.md の「破りようのない構造」）に反する。
4. 方針の引き方が二通りある。設定とブックマークのビルダーは `HostedPanel.settings.placement` などを手書きで引き、`makeSimplePanel` は引数で受ける。設定のビルダーを写して新しいパネルを作ると保存名を共有しうる。
5. `HostedPanelWindowController` が `placement` と `centersOnNextShow` の 2 つの状態を持つが、判定に使うのは「保存名があるか」だけで 1 つに畳める。

## 未確認
指摘 1 の実測はレビュー側のもの（セッションのスクラッチパッドの probe.swift）で、着手時に手元で再現する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 設定窓が最後の位置で開き、サイズは中身に合わせたままであることを、設定窓と同じ構成（resizable: false）のテストで確かめている
- [x] #2 本番で効かない分岐（位置だけ戻す独自処理）が無い、または効く利用者がいる
- [x] #3 共通ビルダーに resizable の既定値が無い
- [x] #4 パネルから配置方針を引く箇所が 1 つだけ
- [x] #5 HostedPanelWindowController の配置に関する状態が、同じ事実を二重に持っていない
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 実測で指摘 1 を再現済み（scratchpad/probe657.swift）: リサイズ不可の窓は setFrameUsingName で保存値の左上だけが戻りサイズは保たれる（restored=(40,278,300,232)、左上 y=510 が保存値と一致）。リサイズ可能な窓は保存値どおり (40,60,610,450)
2. HostedPanelPlacement を .centered / .remember(autosaveName:) の 2 つに畳み、restoreFrame のサイズ戻しと keepsSize を削る。位置だけか位置とサイズかは窓のリサイズ可否から AppKit が決める
3. コントローラーの状態を centersOnNextShow の 1 つにする。記憶する窓かどうかは window.frameAutosaveName から引く
4. HostedPanelPresenter.makeController で panel.placement を 1 回だけ引き、各ビルダーへ渡す。共通ビルダーは Help 配下専用の makeHelpPanel にし（Help 配下はすべてリサイズ可能）、固定サイズの About は init を直接呼ぶ。resizable の既定値は無くなる
5. 設定窓と同じ構成（SettingsView・resizable: false・contentSize nil）で、最後の位置で開きサイズは中身のままであることをテストする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証: HostedPanelWindowControllerTests + SettingsViewSnapshotTests 16 件成功。設定窓と同じ構成のテスト（rememberRestoresOnlyPositionOfSettingsWindow）を追加し、復元を止める変更（centersOnNextShow = true 固定）で同テストとリサイズ可能側のテストが落ちることを確認済み。変更ファイルの swiftlint 0 件。
AC ごとの根拠: AC2 は restoreFrame / keepsSize / rememberPosition / rememberFrame の出現 0（rg）。AC3 は Presenter に Bool の既定値 0（rg）。AC4 は panel.placement の参照が HostedPanelPresenter.makeController の 1 箇所だけ（rg）。AC5 は配置に関する stored property が centersOnNextShow の 1 つだけ。
単純化の判断: makeSimplePanel に placement を足すと引数が 6 個になり function_parameter_count に掛かった。About だけがリサイズ不可なので init を直接呼び、残る Help 配下 4 つの共通ビルダーは resizable を引数に取らず true 固定にした（Help 配下は読み物で可変、は既定値ではなく設計上の事実）。
swift test 全件では 2018 件中 1 件が落ちた。SidebarTreePresenterChildTasksTests の invalidateDropsScheduledRebuild で、単独で 5 回回すと 2 回落ちる既存の flaky。このタスクとは接点が無いので TASK-661 に起票した。それ以外の 2017 件 + CLI 72 件は成功。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
HostedPanelPlacement を .centered / .remember の 2 つに畳んだ。リサイズ不可の設定窓では AppKit 自体が位置だけを戻すため、独自の位置だけ戻す処理は不要だった（実測で確認）。方針は makeController で 1 回だけ引いて渡し、コントローラーの状態は 1 つにし、共通ビルダーから resizable の既定値を無くした。設定窓と同じ構成のテストを足し、復元を止めると落ちることも確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
