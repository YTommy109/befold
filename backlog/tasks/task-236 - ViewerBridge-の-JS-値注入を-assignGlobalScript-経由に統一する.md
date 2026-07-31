---
id: TASK-236
title: ViewerBridge の JS 値注入を assignGlobalScript 経由に統一する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-31 09:16'
updated_date: '2026-07-31 15:28'
labels:
  - refactor
dependencies: []
priority: low
type: task
ordinal: 430000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
BefoldKit/ViewerBridge.swift で window._mmdX への注入経路が二系統ある。hostFeaturesScript / bannerStringsScript / findStringsScript は assignGlobalScript（JSON エンコード経由）だが、initialZoomScript (:51) / systemFontSizeScript (:63) / monoFontFamilyScript (:70, JSONEncoder + フォールバックを手書き) / codeFontSizeScript (:78) / initialFindOptionsScript (:258, JS オブジェクトリテラルを手組み) は素の文字列補間。「JS へ値を注入する = JSON エンコードを通す」というインジェクション対策の規約を 1 経路に統一する。assignGlobalScript の失敗時フォールバックが "{}" 固定なのでスカラー値向けの扱い（型ごとのフォールバック指定など）を決めること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 window._mmdX への注入がすべて共通のエンコード経路を通る
- [x] #2 zoom/フォント/検索オプションの初期値注入が従来どおり動作しテストが通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. assignGlobalScript に fallback 引数を足し、JS 注入の単一経路にする
2. initialZoom / systemFontSize / monoFontFamily / codeFontSize / initialFindOptions を assignGlobalScript 経由へ移す
3. スカラーは fallback を null に統一（JS 側はいずれも未注入=既定として扱うため）
4. FindOptions を Encodable にしてオブジェクトリテラルの手組みを廃止
5. リテラル比較テストの期待値を JSON 表記へ更新し、非有限値の fallback テストを追加
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
assignGlobalScript に fallback 引数を追加し、window._mmd* への注入 5 経路（initialZoom / systemFontSize / monoFontFamily / codeFontSize / initialFindOptions）をすべて JSON エンコード経由へ統一。スカラーのフォールバックは null に決定（JS 側は _mmdInitZoom / markdownFontSize / _mmdInitCodeFont / _mmdInitFind のいずれも未注入値を既定へ落とすため、null が既定復帰と同義になる）。副次的に Double の NaN/Infinity で不正な JS リテラルを吐いていた欠陥も解消（回帰テスト追加）。JSON 化に伴い数値表記が 13.0→13 等に変わるためリテラル比較テストを更新。オブジェクトのキー順は JSONEncoder では不定のため、initialFindOptionsScript のテストは hostFeaturesScript と同じく JSON デコードして検証する形に変更。検証: swift test --skip Integration --skip FileWatcherTests → 934 tests passed。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ViewerBridge の window._mmd* 注入をすべて assignGlobalScript（JSON エンコード）経由に統一し、素の文字列補間を撤去した。スカラーのエンコード失敗時フォールバックは null（JS 側の既定復帰と同義）。非有限 Double で不正な JS を生成していた不具合も解消。swift test 934 件パスで検証。
<!-- SECTION:FINAL_SUMMARY:END -->
