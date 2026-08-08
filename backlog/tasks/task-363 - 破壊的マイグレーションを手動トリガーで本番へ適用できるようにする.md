---
id: TASK-363
title: 破壊的マイグレーションを手動トリガーで本番へ適用できるようにする
status: To Do
assignee: []
created_date: '2026-08-08 07:49'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 624000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
破壊的なマイグレーション（DROP / RENAME / DELETE FROM / TRUNCATE を含むもの）は scripts/check-destructive-migrations.sh が CI の自動デプロイを止める設計になっている（.github/workflows/site.yml、site/README.md）。この歯止め自体は妥当だが、解除手段がローカルからの npm run migrate:remote しかなく、実行者に wrangler の認証が要る。

実際に TASK-362（ts / visitor_day の改名）で詰まった。Claude Code の ! 実行は非対話シェルのため wrangler が OAuth ログインを開けず、'In a non-interactive environment, it's necessary to set a CLOUDFLARE_API_TOKEN environment variable' で失敗する。対話的なターミナルへ移って npx wrangler login から実行し直す必要があった。

site.yml には workflow_dispatch が無く（rg で確認、workflow_dispatch を持つのは verify-dmg.yml のみ）、CI 側の CLOUDFLARE_API_TOKEN を使ってマイグレーションだけを流す手段が無い。

手動トリガーであること自体が『人が内容を確認した』という歯止めになるため、自動デプロイを止める設計とは矛盾しない。マイグレーション適用専用のワークフローを workflow_dispatch で用意する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 workflow_dispatch でマイグレーションのみを本番 D1 へ適用できるワークフローがある
- [ ] #2 適用対象のデータベース（本番 / staging）を入力で選べる
- [ ] #3 実行前に未適用のマイグレーション一覧がログに出る（何が当たるか分からないまま実行できない）
- [ ] #4 通常の push による自動デプロイ経路では、破壊的マイグレーションが引き続き check-destructive-migrations.sh で止まる（歯止めが迂回されていない）
- [ ] #5 手順が site/README.md に記載され、ローカルからの npm run migrate:remote との使い分けが分かる
<!-- AC:END -->
