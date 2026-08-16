---
id: TASK-488.1
title: ページと閲覧言語を events に記録できるようにする
status: To Do
assignee: []
created_date: '2026-08-16 01:44'
updated_date: '2026-08-16 01:50'
labels: []
milestone: m-7
dependencies: []
parent_task_id: TASK-488
priority: medium
ordinal: 718000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488 の記録側。ダッシュボードの表示は TASK-488.2 で扱う。

`events` テーブルにページと言語の情報を持たせ、`/features` を計上する。現状は `/` のみが `visit` として記録され（`site/src/routes/public.tsx:19`）、`/features` は「ページを区別する列が無く LP 指標に混ざるため」意図的に記録していない（同 `:23-34` のコメント）。言語はサーバ側で一切見ておらず、出し分けは `localStorage` の `befold-lang` を読むクライアント JS のみ（`site/src/views/shared.tsx:30-49`）。

このサブタスクで、親タスクに挙げた 2 つの論点（言語をどう判定するか、ページをどう持つか）を確定させる。判定方式を選んだ理由と、その指標が何を意味するか（例: Accept-Language はブラウザ設定であって実際に読んだ言語ではない）を Implementation Notes に残すこと。

ロボット判定は既存の `ua_summary` の `bot:` 接頭辞をそのまま使い、新しい判定を作らない（`site/src/lib/visitor.ts:104-123`、集約点は `site/src/analytics.ts:133,146`）。

スキーマ変更は Atlas 運用に従う（`site/schema/schema.sql` を更新 → `npm run migrate:diff` → `migrate:lint` → `migrate:local`。手順は `site/README.md:59-73`）。テーブル再構築を伴う差分は `scripts/check-destructive-migrations.sh` が検出するため `ADD COLUMN` で足す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /features へのアクセスが events に記録され、/ の visit と区別できる
- [ ] #2 閲覧言語の情報が events に記録される
- [ ] #3 採用した言語判定方式と、その指標が何を意味するかが Implementation Notes に記録されている
- [ ] #4 マイグレーションが Atlas 運用（schema.sql 更新 → diff → lint）で生成され、テーブル再構築を含まない
- [ ] #5 記録処理のユニットテストがあり、ボット判定は既存の ua_summary の仕組みを流用している
- [ ] #6 site の vitest と typecheck が通る
<!-- AC:END -->
