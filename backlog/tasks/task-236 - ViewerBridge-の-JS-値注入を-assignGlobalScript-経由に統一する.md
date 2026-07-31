---
id: TASK-236
title: ViewerBridge の JS 値注入を assignGlobalScript 経由に統一する
status: To Do
assignee: []
created_date: '2026-07-31 09:16'
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
- [ ] #1 window._mmdX への注入がすべて共通のエンコード経路を通る
- [ ] #2 zoom/フォント/検索オプションの初期値注入が従来どおり動作しテストが通る
<!-- AC:END -->
