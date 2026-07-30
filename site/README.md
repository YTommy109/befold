# site — 配布サイト + 分析ダッシュボード (Cloudflare Worker)

<!-- derived-from ./../docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

befold の配布 LP・ダウンロード計測・appcast プロキシ・分析ダッシュボードを
1 つの Cloudflare Worker（Hono / TypeScript）で提供する。

公開 URL: <https://befold.tommy109.workers.dev>（独自ドメインは使わない）

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

## 本番デプロイ（自動）

`main` へのマージで `.github/workflows/site.yml` の `deploy` ジョブが走り、
**D1 マイグレーション適用 → Worker デプロイ** の順に実行される。テスト
（`test` ジョブ）の通過が前提条件。`site/` に変更が無いマージでは起動しない。

手動運用ではこの順序を守り続けられないため CI に固定している。逆順だと
新コードの INSERT がカラム不足で失敗し、`insertEvent` は例外を飲む設計なので
計測が無言で欠落する。

### 必要なシークレット

GitHub リポジトリの Secrets に `CLOUDFLARE_API_TOKEN` を登録する。トークンには
以下の権限が必要。

| 権限 | 用途 |
| ---- | ---- |
| Account / Workers Scripts / Edit | Worker のデプロイ、アセットのアップロード |
| Account / D1 / Edit | マイグレーションの適用 |

### 破壊的なマイグレーションは自動適用されない

`scripts/check-destructive-migrations.sh` が **本番に未適用の**マイグレーションを
走査し、`DROP` / `RENAME` / `DELETE FROM` / `TRUNCATE` を含む場合はデプロイを
失敗させる。D1 は自動バックアップからの巻き戻しが常に間に合うとは限らないため、
取り返しのつかない適用を CI に任せない。

検査対象を未適用のものだけに絞っているので、内容を確認して手動で適用すれば
次回から通るようになる。

```bash
cd site && npm run migrate:remote
```

Atlas はカラム型変更をテーブル再構築（新テーブル作成 → コピー → `DROP` →
`RENAME`）として出力するため、型変更もこの検査で捕捉される。

## staging 環境

公開 URL: <https://befold-staging.tommy109.workers.dev>

本番の分析データを汚さずに、シークレット・バインディング・実 D1・マイグレーション
適用順序といった「本番にしか存在しない条件」を確認するための環境。デプロイ後の
疎通確認はここで行い、本番への確認は記録が走っても意味を持つもの（appcast の
byte 一致など）に絞る。

```bash
npm run migrate:staging   # staging D1 (befold-analytics-staging) へ適用
npm run deploy:staging    # wrangler deploy --env staging
```

**マイグレーションは必ずデプロイより先に当てる。** 順序が逆だと新コードの INSERT が
カラム不足で失敗し、`insertEvent` は例外を飲む設計のため計測が無言で欠落する。

シークレットは Worker 単位なので、staging にも別途登録が必要（未登録だと
`/dashboard` は 503）。

```bash
npx wrangler secret put DASHBOARD_PASSWORD --env staging
```

`--env staging` を付け忘れると本番の値を上書きしてしまうので注意する。

Preview URL（`wrangler versions upload --preview-alias`）はこの環境の代わりに
ならない。バインディングは deploy 対象の設定が使われるため、プレビュー URL でも
書き込み先は本番 D1 になる。データを分離するには環境を分けるしかない。

`wrangler.toml` の `assets` / `d1_databases` / `observability` は非継承キーで、
`[env.staging]` 側に再指定しないと引き継がれない（アセット配信や D1 バインディングが
欠落した Worker ができる）。

## 接続元組織（ASN）の計測

`request.cf.asOrganization`（Cloudflare が解決する AS 保有組織名、例: Google Cloud）を
visit / download / update_check の全イベントで記録する。追加のサブリクエストは発生しない。

- 保存するのは組織名のみで、IP アドレスや厳密な逆引きドメイン（PTR）は使わない。
- 個人の家庭回線では ISP 名（例: NTT Communications）程度の粗い粒度に留まるため、
  生 IP を保存しない・UA は要約のみという既存のプライバシー方針と整合する。
- 企業・クラウド経由の接続では組織名から接続元が推測できる場合がある。これは
  この粒度で許容する仕様上の限界として扱う。
- `request.cf` はローカル開発環境やテストでは付与されないため、未取得時は
  `as_org` を `null` として記録し、イベント自体の記録は継続する
  （`src/events.ts` の `insertEvent`）。

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
