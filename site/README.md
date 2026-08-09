# site — 配布サイト + 分析ダッシュボード (Cloudflare Worker)

<!-- derived-from ./../docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

befold の配布 LP・ダウンロード計測・appcast プロキシ・分析ダッシュボードを
1 つの Cloudflare Worker（Hono / TypeScript）で提供する。

公開 URL: <https://befold.tommy109.workers.dev>（独自ドメインは使わない）

## ルート

| パス | 認証 | 内容 |
| ---- | ---- | ---- |
| `GET /` | 公開 | 配布 LP。`visit` を記録 |
| `GET /download` | 公開 | stable 最新の DMG を R2 から返す。`download`（`source=lp`）を記録 |
| `GET /dl/:tag/:file` | 公開 | 指定タグの DMG を R2 から返す。appcast の enclosure が指す先。`download`（`source=sparkle`）を記録 |
| `GET /appcast.xml` | 公開 | R2 の appcast を返す。`update_check` を記録 |
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
未設定のままだと `/dashboard` は 503 を返す。

```bash
cp .dev.vars.example .dev.vars
curl -u owner:local-dev-password http://127.0.0.1:8787/dashboard
```

worktree では `scripts/worktree-init.sh` がメインリポジトリの `site/.dev.vars` へ
シンボリックリンクを張るため、worktree ごとに作り直す必要はない。実体はメイン側に
1 つだけ置く。

ダッシュボードの見た目を確認するにはデータが要る。ローカル D1 は `site/.wrangler`
配下にあり **worktree ごとに別**なので、worktree を切ったらサンプルデータを入れ直す。

```bash
npm run seed:local   # 直近 14 日ぶんを投入（既存行は削除される）
```

## スキーマ変更（Atlas）

`schema/schema.sql`（desired state）を編集し、差分マイグレーションを生成する。

```bash
npm run migrate:diff -- <migration_name>   # migrations/ に生成
npm run migrate:lint                       # 生成物を検査（適用前に必ず実行）
npm run migrate:local                      # ローカル D1 へ適用
npm run migrate:remote                     # 本番 D1 へ適用
```

Atlas は community 版（`nix`/home-manager 等）で足りる。使うのは SQLite ドライバと
`migrate diff` / `lint` / `hash` / `validate` だけで、official 版が追加で持つ
Atlas Cloud 連携や商用 DB ドライバは使わない。CI も atlas を呼ばない。

### マイグレーションを手書きしたときは hash を打ち直す

`migrations/atlas.sum` は全ファイルのチェックサムを持つ。手書きでファイルを足したり
既存ファイルを編集したりすると次回の `migrate:diff` が checksum mismatch で落ちるため、
`npm run migrate:hash` で打ち直す。`atlas migrate validate --env local` で検証できる。

### RENAME COLUMN は lint が誤検知する

`ALTER TABLE ... RENAME COLUMN` を手書きすると、lint が「列の削除」「非 NULL 列の追加」
として報告する。Atlas が改名を状態差分（その名前の列が消えて別の名前の列が現れた）で
解釈するためで、SQLite の `RENAME COLUMN` は実際にはデータを保持する。

そのため lint の指摘は自動では信用せず、**適用前後の行数と代表値をローカル D1 で
突き合わせて確認する**。実例は TASK-362（`ts` → `timestamp`、`visitor_day` →
`visitor_token`）で、適用前後とも 344 行・`COUNT(DISTINCT visitor_token)` = 122 で
一致することを確認してから本番へ回した。

なお `migrate:diff` に生成させると、Atlas は改名をテーブル再構築
（新テーブル作成 → コピー → `DROP` → `RENAME`）として出力する。改名だけが目的なら
`RENAME COLUMN` を手書きするほうが軽く、既存の索引も貼り直さずに済む。

## デプロイ前の設定

1. D1 を作成し、払い出された ID を `wrangler.toml` の `database_id` に設定する。

   ```bash
   npx wrangler d1 create befold-analytics
   ```

2. リリース成果物の配信元となる R2 バケットを作成する。

   ```bash
   npx wrangler r2 bucket create befold-dist
   ```

   staging も同じバケットを読む。リリース CI は本番バケットにしか put しない
   ため、staging 専用バケットを用意すると常に空になり、R2 経路ではなく GitHub
   フォールバックしか検証できなくなる。Worker は読み取りしかしないので、
   staging が本番成果物を壊すことはない。

3. マイグレーションを本番 D1 へ適用する（`npm run migrate:remote`）。
4. ダッシュボードのパスワードをシークレットとして登録する（**デプロイ前に必須**）。

   ```bash
   npx wrangler secret put DASHBOARD_PASSWORD
   npx wrangler secret put DASHBOARD_USER   # 省略時は owner
   ```

5. `npx wrangler deploy` でデプロイする。

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
| Account / Workers R2 Storage / Edit | リリース成果物と appcast の配置（`release.yml`） |

R2 への書き込みは `release.yml`（リリースタグの push）だけが行う。Worker 側の
`DIST` バインディングは読み取りしか使わない。Sparkle の EdDSA 秘密鍵と
Developer ID 証明書は GitHub Secrets に閉じており、Cloudflare 側には置かない。
`release.yml` は `CLOUDFLARE_ACCOUNT_ID` も参照する。

### 破壊的なマイグレーションは自動適用されない

`scripts/check-destructive-migrations.sh` が **本番に未適用の**マイグレーションを
走査し、`DROP` / `RENAME` / `DELETE FROM` / `TRUNCATE` を含む場合はデプロイを
失敗させる。D1 は自動バックアップからの巻き戻しが常に間に合うとは限らないため、
取り返しのつかない適用を CI に任せない。

Atlas はカラム型変更をテーブル再構築（新テーブル作成 → コピー → `DROP` →
`RENAME`）として出力するため、型変更もこの検査で捕捉される。

検査対象を未適用のものだけに絞っているので、内容を確認して手動で適用すれば
次回から通るようになる。適用手段は 2 つある。

#### GitHub Actions から適用する（推奨）

`Site Migrate` ワークフローを手動実行する（Actions タブ、または `gh`）。CI 側の
`CLOUDFLARE_API_TOKEN` を使うため、手元の wrangler 認証が要らない。

```bash
gh workflow run site-migrate.yml -f environment=production -f mode=plan
# 一覧を確認してから
gh workflow run site-migrate.yml -f environment=production -f mode=apply -f confirm=befold-analytics
```

`mode: plan` は未適用の一覧を出すだけで、何も適用しない。本番へ `apply` する
ときだけ `confirm` にデータベース名の入力を求める。適用後に Worker を反映する
には `Site CI` を再実行する。

#### ローカルから適用する

```bash
cd site && npm run migrate:list     # 未適用の一覧
cd site && npm run migrate:remote   # 適用
```

`wrangler` の認証が要る。**非対話シェル（Claude Code の `!` 実行など）では
OAuth ログインを開けず `CLOUDFLARE_API_TOKEN` の未設定で失敗する**ので、
対話的なターミナルで `npx wrangler login` を済ませてから実行する。

## staging 環境

公開 URL: <https://befold-staging.tommy109.workers.dev>

本番の分析データを汚さずに、シークレット・バインディング・実 D1・マイグレーション
適用順序といった「本番にしか存在しない条件」を確認するための環境。デプロイ後の
疎通確認はここで行い、本番への確認は記録が走っても意味を持つもの（appcast の
byte 一致など）に絞る。appcast の一致確認の手順は
[リリース後の疎通確認（appcast の配信一致）](../docs/dev/development.md#リリース後の疎通確認appcast-の配信一致)
にある。

### staging へ反映する

<!-- constrained-by #破壊的なマイグレーションは自動適用されない -->

`Site Staging` ワークフローを手動実行する。反映したいブランチを選んで実行すると、
型チェック → テスト → マイグレーション適用 → デプロイの順に走る。

```bash
gh workflow run site-staging.yml --ref <ブランチ名>
```

**マイグレーションは必ずデプロイより先に当てる。** 順序が逆だと新コードの INSERT が
カラム不足で失敗し、`insertEvent` は例外を飲む設計のため計測が無言で欠落する。
この順序はワークフローのステップ順として固定してあり、手順の記憶に頼らない。

トリガーが手動なのは、staging が「main へマージする前に任意のブランチを実 D1 で
確認する」場だから。反映するブランチとタイミングは人が選ぶ必要がある。

本番と違い、staging では破壊的マイグレーションを止めない
（[破壊的なマイグレーションは自動適用されない](#破壊的なマイグレーションは自動適用されない)）。
staging のデータは使い捨てで、むしろ `DROP` / `RENAME` を含むマイグレーションを
本番より先にここで当てて確かめるための環境だから。歯止めが要るのは取り返しの
つかない本番データのほうで、そちらは `site.yml` に残っている。

### staging の未適用マイグレーションの検知

同じワークフローが週次（月曜 09:00 JST）で `scripts/check-pending-migrations.sh` を
走らせ、staging D1 に未適用のマイグレーションが 1 件でもあればジョブを失敗させる。
手動トリガーである以上、実行を忘れればスキーマだけ古い状態が残るため
（実際に `20260730022424_add_as_org.sql` が約 10 日間当たっていなかった）。

自動適用にはしていない。スキーマだけ進んでコードが古い状態は、まさにこの検知が
防ぎたいものなので、CI 自身がそれを作ってはならない。未適用に気づいたら
`Site Staging` を実行して、マイグレーションとデプロイをまとめて反映する。

### 手元から直接反映する場合

```bash
npm run migrate:staging   # staging D1 (befold-analytics-staging) へ適用
npm run deploy:staging    # wrangler deploy --env staging
```

`wrangler` の認証が要る。順序を自分で守る必要があるため、通常はワークフローを使う。

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

## ダッシュボードの指標の分け方

<!-- constrained-by ../docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

アクセスを単一の指標として合算せず、`visit` / `download` / `update_check` の
3 指標に分けて表示する。3 つは意味が異なり、合算した数値は解釈できないため
（`visit` はサイト閲覧、`download` は新規獲得、`update_check` は継続利用）。

- OS 別・接続元組織別の内訳は、指標ごとに独立した表として出す
  （例: 「ページアクセス: OS 別」「ダウンロード: 接続元組織別」）。
  3 種を合算した「OS 別」「接続元組織別」の表は**廃止した**（置き換え）。
- 国別・参照元別は「どこから来訪したか」を見る軸で、指標を分けても
  読み取れる情報が増えないため 3 種合算のまま残している。
- 指標の並び順と表示名は `src/analytics.ts` の `KIND_LABELS` が唯一の定義で、
  カード・表の両方がこの順に従う。

## 人間の訪問とロボットの巡回の分離

<!-- constrained-by ../docs/adr/0004-bot-detection-via-user-agent.md -->

JS ビーコンを使わないサーバ側計測なので、クローラの巡回も `visit` として
記録されている。ボットの判別は User-Agent のトークン判定で行う（ADR 0004）。

- ボットと判定した `ua_summary` は `bot:` 接頭辞を付ける
  （`bot:GPTBot` / `bot:Googlebot`、既知トークンに当たらないものは `bot:other`）。
  集計側はボット名を列挙せず `ua_summary LIKE 'bot:%'` だけで分離するため、
  `src/lib/visitor.ts` の `BOT_TOKENS` を増やしても集計側の同期漏れが起きない。
- ボット判定はブラウザ判定より**先に**評価する。現行の Googlebot / Applebot の
  UA は `Chrome/` や `Safari/` を含み、順序を逆にすると人間の訪問として計上される。
- 完全な UA は保存していないため、**過去データは遡って分類できない**。内訳が出るのは
  分類の適用日（2026-08-09）以降だけで、それ以前のクローラの巡回は `other` のまま
  人間側に数えられる。この制約はダッシュボードの注記に出す。
- `bot:other` の比率が高止まりするなら分類漏れのシグナル。トークンを足すか、
  ADR 0004 のトリップワイヤに従って判定方式そのものを見直す。

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
