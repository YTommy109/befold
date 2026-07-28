---
id: TASK-182.1
title: site/ の Worker 雛形を構築する（Hono + Wrangler + D1 + Atlas）
status: To Do
assignee: []
created_date: '2026-07-28 13:35'
labels: []
dependencies: []
documentation:
  - >-
    docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md
parent_task_id: TASK-182
priority: high
ordinal: 258000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
monorepo 内に新ディレクトリ site/ を作り、Hono/TypeScript の Worker 雛形・wrangler.toml・D1 バインディング・Atlas スキーマ管理・Vitest 環境を整える。events テーブルを Atlas で定義しマイグレーションを生成する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 site/ に Hono ベースの Worker があり wrangler dev で起動する
- [ ] #2 D1 に events テーブルが Atlas 生成マイグレーションで作成される（生 IP 非保持のスキーマ）
- [ ] #3 Vitest + @cloudflare/vitest-pool-workers でテストが実行できる
<!-- AC:END -->
