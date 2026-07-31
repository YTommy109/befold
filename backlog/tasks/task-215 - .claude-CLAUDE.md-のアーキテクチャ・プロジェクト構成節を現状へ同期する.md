---
id: TASK-215
title: .claude/CLAUDE.md のアーキテクチャ・プロジェクト構成節を現状へ同期する
status: To Do
assignee: []
created_date: '2026-07-31 03:13'
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
- [ ] #1 .claude/CLAUDE.md のアーキテクチャ節・プロジェクト構成節が現状の実装（BefoldRenderKit / BefoldQuickLook / Sparkle 2 / ViewerRenderer）と一致している
- [ ] #2 native-app-design.md と .claude/CLAUDE.md の間に矛盾する記述が残っていない（縮退・参照化した場合も含む）
<!-- AC:END -->
