# site — 配布サイト + 分析ダッシュボード (Cloudflare Worker)

<!-- derived-from ./../docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

befold の配布 LP・ダウンロード計測・appcast プロキシ・分析ダッシュボードを
1 つの Cloudflare Worker（Hono / TypeScript）で提供する。

公開 URL: <https://befold-site.tokutomi.workers.dev>（独自ドメインは使わない）

## ルート

| パス | 認証 | 内容 |
| ---- | ---- | ---- |
| `GET /` | 公開 | 配布 LP。`visit` を記録 |
| `GET /download` | 公開 | 最新リリースの DMG へ 302。`download` を記録 |
| `GET /appcast.xml` | 公開 | GitHub の appcast をプロキシ。`update_check` を記録 |
| `GET /appcast-develop.xml` | 公開 | 同上（develop チャンネル） |
| `GET /dashboard` | Basic 認証 | 集計ダッシュボード |
| `GET /dashboard/stream` | Basic 認証 | SSE（D1 ポーリング型）で新着イベントを push |

## 開発

```bash
npm install
npm run migrate:local   # ローカル D1 にマイグレーションを適用
npm run dev             # wrangler dev
npm test                # vitest（@cloudflare/vitest-pool-workers）
npm run typecheck
```

ローカルの認証情報は `.dev.vars`（gitignore 対象）に置く。`.dev.vars.example` をコピーして使う。

```bash
cp .dev.vars.example .dev.vars
curl -u owner:local-dev-password http://127.0.0.1:8787/dashboard
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
3. ダッシュボードのパスワードをシークレットとして登録する（**デプロイ前に必須**）。

   ```bash
   npx wrangler secret put DASHBOARD_PASSWORD
   npx wrangler secret put DASHBOARD_USER   # 省略時は owner
   ```

4. `npx wrangler deploy` でデプロイする。

   `wrangler secret put` を非対話シェル（Claude Code の `!` 実行など）で走らせると
   入力を受け取れず空の値が登録される。ダッシュボードが 503 を返す場合はこれを疑い、
   対話的なターミナルで登録し直す。

## ダッシュボードの認証方式

独自ドメインを使わず `*.workers.dev` で公開するため、Cloudflare Access は使えない
（Access のアプリケーションは自アカウントのゾーンのホスト名にしか設定できず、
workers.dev は Cloudflare 所有のドメインであるため）。代わりに Worker 側の
Basic 認証で `/dashboard` と `/dashboard/stream` を保護する。

- パスワードはシークレット `DASHBOARD_PASSWORD`。コードや wrangler.toml には置かない。
- 未設定のままデプロイされた場合は素通しさせず 503 で閉じる。
- ブラウザは一度認証すると同一オリジンの後続リクエストにも認証情報を送るため、
  ヘッダを設定できない `EventSource`（SSE）もそのまま動作する。
- 将来 Cloudflare 管理下のドメインを使う場合は、Access（所有者メールのみ許可）へ
  切り替えたうえでこの Basic 認証を撤去できる。
