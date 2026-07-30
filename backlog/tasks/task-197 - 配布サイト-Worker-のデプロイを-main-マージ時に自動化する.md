---
id: TASK-197
title: 配布サイト Worker のデプロイを main マージ時に自動化する
status: To Do
assignee: []
created_date: '2026-07-30 00:07'
labels: []
dependencies:
  - TASK-196
priority: medium
ordinal: 280000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在 Worker のデプロイは手動の npx wrangler deploy で、D1 マイグレーションの適用（migrate:remote）も手動。この 2 手は順序を間違えると静かに壊れる。マイグレーションを先に当てないと新コードの INSERT がカラム不足で失敗し、insertEvent は例外を飲む設計のため計測が無言で欠落する（TASK-182.6 の実装時に実際にこの順序制約に直面した）。

人間の記憶に依存させず、main へのマージで migrate:remote → deploy の順に実行されるようにする。

前提と論点:
- GitHub Secrets に CLOUDFLARE_API_TOKEN を登録する必要があり、これはユーザーの操作。トークンを置きたくない場合は Cloudflare 側の Git 連携（Workers Builds）でリポジトリを繋ぐ代替がある。着手時にどちらを採るか確認する。
- マイグレーションの自動適用は前進のみ安全。カラム削除や型変更のような破壊的変更を自動で流すのは危険なので、破壊的変更を検知したら止める、あるいは破壊的変更だけ手動運用にする方針をあわせて決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 main へのマージで Worker が自動デプロイされる
- [ ] #2 デプロイ前に D1 マイグレーションが適用され、順序が逆転しない
- [ ] #3 site/ に変更が無いマージではデプロイが走らない
- [ ] #4 破壊的なマイグレーションの扱い（自動適用するか止めるか）が決定され site/README.md に記載される
<!-- AC:END -->
