---
id: TASK-181
title: ソースコードビューのフォント設定（等幅ファミリー＋サイズ）を実装する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:15'
updated_date: '2026-07-28 15:50'
labels: []
dependencies:
  - TASK-180
priority: medium
ordinal: 256000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ソースコードビューの等幅フォントのファミリーと絶対 pt サイズを設定できるようにする。ファミリーはソースビュー＋Markdown プレビュー内コード両方に連動、サイズはソースビューのみ。設定はグローバルで開いている全ウィンドウへライブ反映。既存の CSS 変数注入パイプライン（ViewerBridge → viewer-main.js → style.css）に相乗りする。設定 UI は AppKit の NSWindowController が SwiftUI をホスト（ADR 0001 の方針、Cmd+,）。開発中は TASK-180 のフィーチャーゲートで囲い dev/DEBUG のみ露出する（ゲートの最初の実利用者を兼ねる）。設計: docs/superpowers/specs/2026-07-28-code-font-settings-design.md、計画: docs/superpowers/plans/2026-07-28-code-font-settings.md。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 等幅フォントのファミリーをキュレートリスト（＋システム既定）から選べ、ソースビューとプレビュー内コード両方に反映される
- [x] #2 コードフォントの絶対 pt サイズを設定でき、ソースビューのみに反映される（プレビュー内コードのサイズは従来どおり本文×0.75）
- [x] #3 設定はグローバルに永続化され、開いている全ウィンドウへライブ反映される
- [x] #4 ズームは従来どおり上乗せで効く（本設定はベースサイズを決めるだけ）
- [x] #5 設定メニュー・ウィンドウは FeatureGate.inProgressFeaturesEnabled で囲われ、stable ビルドでは露出しない
- [x] #6 CodeFontPreference・MonospaceFontCatalog 整形・ViewerBridge 注入スクリプトにユニットテストがある
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実装完了(11 タスク)。CodeFontPreference(UserDefaults 永続化, size clamp[6,32] default10), MonospaceFontCatalog(純関数整形+システム列挙), ViewerBridge.monoFontFamilyScript/codeFontSizeScript/applyCodeFontScript(JSON/CSS エスケープ), viewer-main.js _mmdInitCodeFont(CSS 変数 --mmd-mono-font-family / --mmd-code-font-size, pt*16/13), style.css(fallback は monospace スタックで既定挙動維持), 共有 CodeFontPreference DI(AppDelegate→ViewerWindowManager→Controller, hiddenFilesPreference と同型), 初回注入+applyCodeFontToAllWindows ライブ更新, 設定ウィンドウ/Cmd+, は FeatureGate で dev/DEBUG のみ露出, l10n 7 キー en/ja 揃い。swift test 838/838 PASS。単体テスト: CodeFontPreference/MonospaceFontCatalog/ViewerBridge。CSS 適用先分離(ファミリー=両方/サイズ=ソースのみ)と zoom 非干渉は opus 最終レビューで CSS セマンティクス検証。実画面レンダリング/複数ウィンドウ ライブ反映は規約通りリリース前手動 GUI 確認対象。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
ソースビューの等幅フォント(ファミリー=ソース+プレビュー内コード, 絶対 pt サイズ=ソースのみ)を設定可能に。既存 CSS 変数注入パイプライン(ViewerBridge→viewer-main.js→style.css)へ相乗りし、共有 CodeFontPreference を全ウィンドウへライブ反映。設定 UI は FeatureGate で dev/DEBUG 限定露出。単体テスト(838/838)と opus 最終レビュー(Critical 1件=既定時プレビュー非等幅回帰を修正 7545cde9)で検証。実描画は規約通りリリース前手動 GUI 確認。
<!-- SECTION:FINAL_SUMMARY:END -->
