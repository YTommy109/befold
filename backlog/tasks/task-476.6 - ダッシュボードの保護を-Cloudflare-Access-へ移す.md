---
id: TASK-476.6
title: ダッシュボードの保護を Cloudflare Access へ移す
status: To Do
assignee: []
created_date: '2026-08-13 14:21'
labels:
  - site
dependencies:
  - TASK-476.1
  - TASK-476.2
  - TASK-476.3
parent_task_id: TASK-476
priority: low
ordinal: 101600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
独自ドメイン配下になることで Cloudflare Access が使えるようになる。現状は workers.dev に Access を張れないという制約から Worker 側の Basic 認証（シークレット DASHBOARD_PASSWORD）で保護している（site/wrangler.toml のコメント、site/src/routes/dashboard.tsx:16）。

TASK-476.1 の ADR で「Access へ移す」と決まった場合のみ実施する。決まらなければクローズする。

注意点:
- 旧ホスト（workers.dev）が生きている間は、そちらからダッシュボードへ到達できる経路を塞ぐ必要がある。Access はホスト単位なので、旧ホストの /dashboard は 404 か新ドメインへの 301 にする。
- Basic 認証を撤去するなら DASHBOARD_PASSWORD シークレットも削除し、関連するテスト・ドキュメントを更新する。
- SSE（リアルタイム更新）が Access 経由で動くことを実測で確認する。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 新ドメインの /dashboard が Access で保護され、認証後に集計と SSE が従来どおり動作する
- [ ] #2 旧ホストからダッシュボードへ到達できない
- [ ] #3 Basic 認証の実装・シークレット・テスト・ドキュメントの記述が整理されている
<!-- AC:END -->
