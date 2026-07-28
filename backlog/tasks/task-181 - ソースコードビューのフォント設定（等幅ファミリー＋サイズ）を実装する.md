---
id: TASK-181
title: ソースコードビューのフォント設定（等幅ファミリー＋サイズ）を実装する
status: To Do
assignee: []
created_date: '2026-07-28 13:15'
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
- [ ] #1 等幅フォントのファミリーをキュレートリスト（＋システム既定）から選べ、ソースビューとプレビュー内コード両方に反映される
- [ ] #2 コードフォントの絶対 pt サイズを設定でき、ソースビューのみに反映される（プレビュー内コードのサイズは従来どおり本文×0.75）
- [ ] #3 設定はグローバルに永続化され、開いている全ウィンドウへライブ反映される
- [ ] #4 ズームは従来どおり上乗せで効く（本設定はベースサイズを決めるだけ）
- [ ] #5 設定メニュー・ウィンドウは FeatureGate.inProgressFeaturesEnabled で囲われ、stable ビルドでは露出しない
- [ ] #6 CodeFontPreference・MonospaceFontCatalog 整形・ViewerBridge 注入スクリプトにユニットテストがある
<!-- AC:END -->
