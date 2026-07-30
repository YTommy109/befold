---
id: TASK-193
title: コードフォントのベースサイズ注入を stable でゲートするか判断する
status: Done
assignee:
  - '@tokutomi'
created_date: '2026-07-28 15:51'
updated_date: '2026-07-30 05:03'
labels: []
dependencies: []
ordinal: 263500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現状 codeFontSizePoints は常に注入され(既定 10pt≈12.3px)、stable でもソースビューのサイズがシステム/アクセシビリティ文字サイズに追従しなくなる(従来は calc(本文*0.75) で追従)。既定の見た目差は僅少(12.3 vs 12px)だが、stable でアクセシビリティ文字サイズ追従を保ちたい場合はサイズ注入を FeatureGate で囲うか、未設定時は size 変数を注入しない設計にする。要判断。opus 最終レビューの Minor 指摘由来。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 stable でのソースビュー サイズがアクセシビリティ文字サイズに追従すべきか方針決定し、必要なら実装する
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. CodeFontPreference.fontSizePoints を Double? 化(nil=未カスタマイズ)。fontFamily と同じ「nil=フォールバック」規約を踏襲\n2. ViewerBridge.codeFontSizeScript/applyCodeFontScript の points を Double? に変更、nil は window._mmdCodeFontSize=null を注入(viewer-main.js は既に非数値で removeProperty→CSS calc(0.75)フォールバックする実装済み)\n3. ViewerRenderer.makeWebView の codeFontSizePoints デフォルトを nil に変更\n4. ViewerContentView/ViewerWebView/WebViewCommandController の型伝搬を Double? に更新\n5. CodeFontSettingsView は preference.fontSizePoints ?? defaultPoints でスライダー初期値表示、変更時のみ preference に書き込み(customize)\n6. CodeFontPreferenceTests の未設定時テストを nil 期待に更新\n7. swift build / swift test で確認
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
既存の nil=フォールバック規約(fontFamily と同様)を CodeFontPreference.fontSizePoints にも適用する形で単純化を検討し、新規状態や FeatureGate 分岐を追加せずに実装した。未カスタマイズ時(stable では常に該当)は window._mmdCodeFontSize に null を注入し、viewer-main.js の既存ロジックで CSS calc(本文*0.75) フォールバックへ委ねる。設定 UI(dev/prerelease限定)で明示変更した場合のみ固定pxを注入する。swift test --skip Integration --skip FileWatcherTests: 786 tests in 105 suites passed.
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
CodeFontPreference.fontSizePoints を Double? 化し、未カスタマイズ時は CSS 側のアクセシビリティ追従フォールバック(calc(本文*0.75))を使うよう変更。ViewerBridge/ViewerRenderer/ViewerContentView/ViewerWebView/WebViewCommandController/CodeFontSettingsView の型を Double? に伝搬。テスト: swift test --skip Integration --skip FileWatcherTests で 786 tests 全pass。
<!-- SECTION:FINAL_SUMMARY:END -->
