---
id: TASK-656
title: ブックマーク管理ウィンドウが毎回中央で開き直され、ユーザーが動かした位置とサイズが保たれない
status: To Do
assignee: []
created_date: '2026-09-28 05:53'
updated_date: '2026-09-28 05:57'
labels:
  - bug
  - ui
dependencies: []
priority: medium
type: bug
ordinal: 856000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 現象
⌘⇧D で開くブックマーク管理ウィンドウを移動・リサイズして閉じても、次に開くと毎回画面中央・初期サイズに戻る。ユーザーが最後に置いた位置とサイズで開いてほしい。

## 原因（コード参照）
`HostedPanelWindowController.showAndActivate()`（BefoldApp/befold/App/HostedPanelWindowController.swift）が開くたびに無条件で `window?.center()` を呼んでいる。枠の保存（`setFrameAutosaveName` 等）もしていないため、アプリ再起動をまたいでも復元されない。

## 影響範囲
同じコントローラーを About・設定・ブックマーク・Help 配下（機能概要・キーボードショートカット・AI 連携・OSS ライセンス）の全パネルが共有している（HostedPanelPresenter.swift）。ブックマークだけ直すか、全パネルで位置を保つかは着手時に決める（固定サイズの About・設定は位置だけ、可変の Help 系はサイズも、など）。

## 未確認
- アプリ再起動後も復元すべきか（同一起動中だけでよいか）。`setFrameAutosaveName` なら再起動もまたげる。
- 保存位置が現在の画面構成の外になった場合の扱い（AppKit の frame autosave は画面内に補正されるはずだが実測していない）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 ブックマーク管理ウィンドウを移動・リサイズして閉じ、再度 ⌘⇧D で開くと、最後の位置とサイズで開く
- [ ] #2 初回（保存値なし）は従来どおり中央に開く
- [x] #3 他のパネルへの適用範囲を決め、その判断を Implementation Notes に残す
- [ ] #4 位置を保つ振る舞いが破れたら落ちるテストがある
- [ ] #5 About・Help 配下など読むだけのパネルは従来どおり毎回中央で開く
- [ ] #6 設定ウィンドウは最後の位置で開く（サイズは従来どおり中身に合わせる）
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
適用範囲（ユーザー判断 2026-09-28）: 読むだけのパネル（About・機能概要・キーボードショートカット・AI 連携・OSS ライセンス）は従来どおり毎回中央で開く。位置を保つのはブックマーク管理ウィンドウ。設定ウィンドウ（編集するが固定サイズ）をどちらに入れるかは未決。着手時にユーザーへ確認する。

設定ウィンドウ（ユーザー判断 2026-09-28）: 位置だけ保つ。サイズは中身に合わせる現状のまま（固定サイズで、ホスティングビューの固有サイズに従う）。これで適用範囲は確定。
<!-- SECTION:NOTES:END -->
