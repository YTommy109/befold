---
id: TASK-215
title: .claude/CLAUDE.md のアーキテクチャ・プロジェクト構成節を現状へ同期する
status: Done
assignee:
  - '@claude'
created_date: '2026-07-31 03:13'
updated_date: '2026-07-31 08:34'
labels: []
dependencies: []
priority: medium
ordinal: 289500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
コミット 9a555c9 のコードレビュー指摘（CONFIRMED）。docs/dev/native-app-design.md のアーキテクチャ図とモジュール構成ツリーは BefoldRenderKit / BefoldQuickLook / Sparkle 2 を含む現状へ更新されたが、同内容を重複記載している .claude/CLAUDE.md のアーキテクチャ／プロジェクト構成節は旧構成のまま残り、矛盾する 2 つの説明が併存している。

.claude/CLAUDE.md は全セッションで読み込まれるため影響が大きい: プロジェクト構成に BefoldRenderKit も BefoldQuickLook も無く、ViewerWebView の説明も「ViewerBridge 経由で evaluateJavaScript」と ViewerRenderer 導入前のまま。以後のセッションで Claude や開発者が旧構成を前提に判断するリスクがある（例: 描画変更時に BefoldRenderKit/ViewerRenderer の存在を見落とす）。

あわせて、native-app-design.md との二重管理を続けるか、CLAUDE.md 側を要約＋docs/dev への参照に縮退するかも検討する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 .claude/CLAUDE.md のアーキテクチャ節・プロジェクト構成節が現状の実装（BefoldRenderKit / BefoldQuickLook / Sparkle 2 / ViewerRenderer）と一致している
- [x] #2 native-app-design.md と .claude/CLAUDE.md の間に矛盾する記述が残っていない（縮退・参照化した場合も含む）
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. docs/dev/native-app-design.md の最新版（TASK-216 ブランチ）と実コードで現状構成を確認する
2. .claude/CLAUDE.md のアーキテクチャ節を、主要モジュール（befold.app / BefoldKit / BefoldRenderKit / BefoldQuickLook / BefoldCLI / befold-cli）の一行責務 + データフロー一行要約に縮退する（構成図は再掲しない）
3. プロジェクト構成節を削除し、アーキテクチャ節の末尾に docs/dev/native-app-design.md への参照を明示する
4. 他の節（技術スタック以降）は変更しない
5. AC を最新の native-app-design.md に対して検証し、docs: プレフィックスでコミットする
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
縮退案を採用。.claude/CLAUDE.md のアーキテクチャ節を主要ターゲット責務表＋データフロー3行に縮退し、プロジェクト構成節（構成ツリー再掲）は削除して docs/dev/native-app-design.md への参照に一本化した。

検証:
- 記述内容は実コードで確認（BefoldApp/ 直下のターゲット一覧、BefoldRenderKit/ViewerRenderer*.swift、BefoldQuickLook/PreviewViewController.swift、befold/Updates/UpdateChannel.swift、AppDelegate.swift:22 の SPUStandardUpdaterController、ViewerWebView.swift が ViewerRenderer を Coordinator として保持、BefoldKit/Resources/ の同梱アセット）
- AC#2 は TASK-216 の最新版（git show origin/docs/task-216:docs/dev/native-app-design.md）と突き合わせて確認。構成ツリー等の重複記載を削除したため矛盾の余地自体が消えた
- 参照リンク ../docs/dev/native-app-design.md が実在することを確認
- 他の節（技術スタック / コマンド / Swift コーディング規約 / テスト規約 / 完了基準 / コミット規約 / フィーチャーゲート）は未変更
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
.claude/CLAUDE.md のアーキテクチャ節・プロジェクト構成節を、簡潔な要約＋docs/dev/native-app-design.md への参照に縮退し二重管理を解消した。要約の内容（BefoldRenderKit / BefoldQuickLook / ViewerRenderer / Sparkle 2）は実コードで確認し、最新の native-app-design.md と矛盾しないことを確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
