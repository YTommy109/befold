---
id: TASK-657
title: パネル窓の配置方針に本番で効かない分岐と重複した状態が残っている（TASK-656 のレビュー指摘）
status: To Do
assignee: []
created_date: '2026-09-28 06:29'
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
- [ ] #1 設定窓が最後の位置で開き、サイズは中身に合わせたままであることを、設定窓と同じ構成（resizable: false）のテストで確かめている
- [ ] #2 本番で効かない分岐（位置だけ戻す独自処理）が無い、または効く利用者がいる
- [ ] #3 共通ビルダーに resizable の既定値が無い
- [ ] #4 パネルから配置方針を引く箇所が 1 つだけ
- [ ] #5 HostedPanelWindowController の配置に関する状態が、同じ事実を二重に持っていない
<!-- AC:END -->
