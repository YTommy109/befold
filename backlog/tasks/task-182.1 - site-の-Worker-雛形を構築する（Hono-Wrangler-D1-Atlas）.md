---
id: TASK-182.1
title: site/ の Worker 雛形を構築する（Hono + Wrangler + D1 + Atlas）
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-28 13:35'
updated_date: '2026-07-28 16:57'
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
- [x] #1 site/ に Hono ベースの Worker があり wrangler dev で起動する
- [x] #2 D1 に events テーブルが Atlas 生成マイグレーションで作成される（生 IP 非保持のスキーマ）
- [x] #3 Vitest + @cloudflare/vitest-pool-workers でテストが実行できる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. site/ に npm プロジェクトを作成（package.json / tsconfig.json）し、hono・zod・wrangler・vitest・@cloudflare/vitest-pool-workers を導入する
2. wrangler.toml を作成し、Worker 名・compatibility_date・D1 バインディング(DB)・migrations_dir を定義する
3. schema/schema.sql に events テーブル（生 IP 非保持）と索引を定義し、atlas.hcl で sqlite dev-db を desired state として設定、atlas migrate diff で migrations/ を生成する
4. src/index.ts に Hono エントリを置き、ヘルスチェック相当の最小ルートを実装する（本格ルートは TASK-182.2）
5. test/ に Vitest + @cloudflare/vitest-pool-workers 環境を用意し、マイグレーション適用後に events テーブルへ INSERT/SELECT できることをテストする
6. wrangler dev の起動確認・vitest 実行確認・.gitignore 追記を行う
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
検証ログ:
- `wrangler dev --port 8788 --local` 起動 → `GET /healthz 200 OK`（curl で 'ok' を取得）
- `wrangler d1 migrations apply befold-analytics --local` → 20260728165331_init_events.sql 適用成功（4 commands executed）
- `vitest run` → 2 tests passed（マイグレーション適用済み D1 への INSERT/SELECT、zod の kind 検証）
- `tsc --noEmit` → エラーなし

設計上の判断:
- Atlas は既定フォーマット（1 マイグレーション = 1 ファイル）を使用。golang-migrate 等の up/down 2 ファイル形式は wrangler d1 migrations が適用できないため。
- 型は @cloudflare/workers-types をやめ `wrangler types` 生成の worker-configuration.d.ts（Cloudflare.Env）に統一。wrangler.toml を唯一の定義元にできるため。生成物はコミットする。
- @cloudflare/vitest-pool-workers は v0.18 系で API が変わり、defineWorkersConfig ではなく Vite プラグイン cloudflareTest() を使う（vitest 4 対応）。
- wrangler.toml の database_id はプレースホルダ。実デプロイ前に `wrangler d1 create` の払い出し ID へ差し替える。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
site/ に Hono + Wrangler + D1 + Atlas + Vitest の Worker 雛形を新設した。schema/schema.sql を desired state として Atlas で events テーブル（生 IP 非保持）のマイグレーションを生成し、wrangler d1 migrations apply --local で適用できることを確認。テストは @cloudflare/vitest-pool-workers（cloudflareTest プラグイン）で D1 バインディングごと実行し、マイグレーション適用後の INSERT/SELECT と zod 検証が通ることを確認した。wrangler dev で /healthz が 200 を返すことも確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
