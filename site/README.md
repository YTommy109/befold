# site — 配布サイト + 分析ダッシュボード (Cloudflare Worker)

<!-- derived-from ./../docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

befold の配布 LP・ダウンロード計測・appcast プロキシ・分析ダッシュボードを
1 つの Cloudflare Worker（Hono / TypeScript）で提供する。

## ルート

| パス | 認証 | 内容 |
| ---- | ---- | ---- |
| `GET /` | 公開 | 配布 LP。`visit` を記録 |
| `GET /download` | 公開 | 最新リリースの DMG へ 302。`download` を記録 |
| `GET /appcast.xml` | 公開 | GitHub の appcast をプロキシ。`update_check` を記録 |
| `GET /appcast-develop.xml` | 公開 | 同上（develop チャンネル） |
| `GET /dashboard` | Access | 集計ダッシュボード |
| `GET /dashboard/stream` | Access | SSE（D1 ポーリング型）で新着イベントを push |

## 開発

```bash
npm install
npm run migrate:local   # ローカル D1 にマイグレーションを適用
npm run dev             # wrangler dev
npm test                # vitest（@cloudflare/vitest-pool-workers）
npm run typecheck
```

ダッシュボードはローカルでは Access を通らないため、ヘッダを自分で付けて確認する。

```bash
curl -H 'Cf-Access-Jwt-Assertion: local' http://127.0.0.1:8787/dashboard
```

## スキーマ変更（Atlas）

`schema/schema.sql`（desired state）を編集し、差分マイグレーションを生成する。

```bash
npm run migrate:diff -- <migration_name>   # migrations/ に生成
npm run migrate:local                      # ローカル D1 へ適用
npm run migrate:remote                     # 本番 D1 へ適用
```

## デプロイ前の設定

1. D1 を作成し、払い出された ID を `wrangler.toml` の `database_id` に設定する。

   ```bash
   npx wrangler d1 create befold-analytics
   ```

2. マイグレーションを本番 D1 へ適用する（`npm run migrate:remote`）。
3. カスタムドメインのルートを設定する（`*.workers.dev` は `workers_dev = false` で無効化済み。
   Access が掛からない経路を残さないため）。
4. Cloudflare Access（Zero Trust）で `/dashboard` を保護する。

### Cloudflare Access の設定手順

Zero Trust ダッシュボード → **Access → Applications → Add an application → Self-hosted**:

- **Application name**: `befold analytics`
- **Session duration**: 任意（既定の 24h で可）
- **Public hostname**: 配布サイトのドメイン、**Path**: `dashboard`
  （`/dashboard` と `/dashboard/stream` の両方が配下に入る）
- **Policy**: Action = `Allow`、Include = `Emails` → 所有者のメールアドレスのみ

Worker 側はポリシー内容を持たない。Access が付与する `Cf-Access-Jwt-Assertion`
ヘッダの有無だけを確認し、Access を経由しないアクセスを 403 で拒否する（多層防御）。
