---
id: TASK-656
title: ブックマーク管理ウィンドウが毎回中央で開き直され、ユーザーが動かした位置とサイズが保たれない
status: Done
assignee:
  - '@claude'
created_date: '2026-09-28 05:53'
updated_date: '2026-09-28 06:05'
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
- [x] #1 ブックマーク管理ウィンドウを移動・リサイズして閉じ、再度 ⌘⇧D で開くと、最後の位置とサイズで開く
- [x] #2 初回（保存値なし）は従来どおり中央に開く
- [x] #3 他のパネルへの適用範囲を決め、その判断を Implementation Notes に残す
- [x] #4 位置を保つ振る舞いが破れたら落ちるテストがある
- [x] #5 About・Help 配下など読むだけのパネルは従来どおり毎回中央で開く
- [x] #6 設定ウィンドウは最後の位置で開く（サイズは従来どおり中身に合わせる）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 配置方針 HostedPanelPlacement（centered / rememberFrame / rememberPosition）を HostedPanelWindowController の必須引数にする
2. パネルごとの方針は HostedPanel.placement（網羅的な switch）の 1 箇所に置き、Presenter はそれを渡すだけにする
3. remember 系は NSWindow の frame autosave（setFrameUsingName + setFrameAutosaveName）に乗る。保存値が無い初回だけ中央。rememberPosition は復元後にサイズを戻し左上を固定する
4. showAndActivate の無条件 center() を、centered の毎回と remember 系の初回だけにする
5. テストで保存値あり→復元・同一起動中の再表示・位置だけ復元・初回中央・centered の毎回中央・パネルごとの方針を担保する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
適用範囲（ユーザー判断 2026-09-28）: 読むだけのパネル（About・機能概要・キーボードショートカット・AI 連携・OSS ライセンス）は従来どおり毎回中央で開く。位置を保つのはブックマーク管理ウィンドウ。設定ウィンドウ（編集するが固定サイズ）をどちらに入れるかは未決。着手時にユーザーへ確認する。

設定ウィンドウ（ユーザー判断 2026-09-28）: 位置だけ保つ。サイズは中身に合わせる現状のまま（固定サイズで、ホスティングビューの固有サイズに従う）。これで適用範囲は確定。

検証: swift test 全件成功（2017 + 72 件）。HostedPanelWindowControllerTests に位置の 6 件を追加。showAndActivate を旧来の無条件 center() へ戻すと 3 件が落ちることを確認済み（ミューテーション確認）。xcodebuild build も成功（main で FeatureGate.swift が消えていたため xcodegen generate で .xcodeproj を再生成）。
AC1/AC6 は実機の ⌘⇧D では確かめていない。インストール済みの befold（同じバンドル ID com.degino.befold）が起動中で、Debug ビルドを並べて起動すると衝突し、利用者の defaults に枠の値を書き込むため。代わりに、枠の復元をコントローラーの単体テストで、パネルとの対応を HostedPanel.placement のテストで担保した。frame autosave のキーは standard defaults の 'NSWindow Frame BookmarkManagerWindow' / 'NSWindow Frame SettingsWindow'。
単純化: パネルごとの方針を Presenter の各ビルダーに散らさず HostedPanel.placement へ集約した。読むだけのパネル 5 つは makeSimplePanel に畳み、makeController の function_body_length 超過も解消した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ブックマーク管理ウィンドウが最後の位置とサイズで、設定ウィンドウが最後の位置で開くようにした。About・Help 配下は従来どおり毎回中央。方針は HostedPanel.placement に集約し、NSWindow の frame autosave で保存する。保存値が無い初回だけ中央に置く。単体テスト 7 件で担保し、修正を戻すと落ちることも確認した。実機での ⌘⇧D の確認は、インストール版が起動中のため未実施。
<!-- SECTION:FINAL_SUMMARY:END -->
