# site — 配布サイト + 分析ダッシュボード (Cloudflare Worker)

<!-- derived-from ./../docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

befold の配布 LP・ダウンロード計測・appcast プロキシ・分析ダッシュボードを
1 つの Cloudflare Worker（Hono / TypeScript）で提供する。

公開 URL: <https://befold.degino.com>（旧 URL <https://befold.tommy109.workers.dev> も恒久的に併存する。理由は [ADR 0007](../docs/adr/0007-distribution-site-custom-domain.md)）

## ルート

| パス | 認証 | 内容 |
| ---- | ---- | ---- |
| `GET /` | 公開 | 配布 LP（日本語）。`visit`（`page=/`, `display_lang=ja`）を記録 |
| `GET /en` | 公開 | 配布 LP（英語）。`visit`（`page=/`, `display_lang=en`）を記録 |
| `GET /features` | 公開 | 機能・対応ファイルタイプの詳細ページ（日本語）。`visit`（`page=/features`, `display_lang=ja`）を記録 |
| `GET /en/features` | 公開 | 同上（英語）。`visit`（`page=/features`, `display_lang=en`）を記録 |
| `GET /download` | 公開 | stable 最新の DMG を R2 から返す。`download`（`source=lp`）を記録 |
| `GET /dl/:tag/:file` | 公開 | 指定タグの DMG を R2 から返す。appcast の enclosure が指す先。`download`（`source=sparkle`）を記録 |
| `GET /appcast.xml` | 公開 | R2 の appcast を返す。`update_check` を記録 |
| `GET /appcast-develop.xml` | 公開 | 同上（develop チャンネル） |
| `GET /dashboard` | Cloudflare Access | 集計ダッシュボード。旧ホストでは 404 |
| `GET /dashboard/stream` | Cloudflare Access | SSE（D1 ポーリング型）で新着イベントを push。旧ホストでは 404 |
| `GET /dashboard/events` | Cloudflare Access | イベント一覧。`?before=` / `?after=` の id カーソルで 100 件ずつ遡る。旧ホストでは 404 |
| その他 | 公開 | 静的アセット（`public/`）。無ければ LP の意匠の 404 ページ。**何も記録しない** |

## 開発

```bash
npm install
npm run migrate:local   # ローカル D1 にマイグレーションを適用
npm run dev             # wrangler dev
npm test                # vitest（@cloudflare/vitest-pool-workers）
npm run typecheck
```

ローカルの設定は `.dev.vars`（gitignore 対象）に置く。`.dev.vars.example` をコピーして使う。

ローカルでは Access を経由しないため、`/dashboard` は **ホストが localhost で、かつ
`ACCESS_TEAM_DOMAIN` / `ACCESS_AUD` が未設定のとき**だけ素通しする。どちらか一方でも
欠けると通らない（設定済みの本番ではホストに関わらず JWT 検証に入る）。

```bash
cp .dev.vars.example .dev.vars
curl http://127.0.0.1:8787/dashboard
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
4. Cloudflare Access の self-hosted アプリケーションを作り、`wrangler.toml` の
   `ACCESS_TEAM_DOMAIN` / `ACCESS_AUD` を埋める（**デプロイ前に必須**）。手順は
   下の「ダッシュボードの認証方式」を参照。値が空のままだと `/dashboard` は 503 で
   閉じる（素通しにはしない）。

5. `npx wrangler deploy` でデプロイする。

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

公開 URL: <https://staging.befold.degino.com>（旧 URL <https://befold-staging.tommy109.workers.dev> も併存する）

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

Access のアプリケーションはホスト単位なので、staging（`staging.befold.degino.com`）
にも別途作成し、`[env.staging.vars]` の `ACCESS_AUD` を埋める必要がある（空のままだと
`/dashboard` は 503）。team domain はアカウント共通なので本番と同じ値でよい。

Preview URL（`wrangler versions upload --preview-alias`）はこの環境の代わりに
ならない。バインディングは deploy 対象の設定が使われるため、プレビュー URL でも
書き込み先は本番 D1 になる。データを分離するには環境を分けるしかない。

`wrangler.toml` の `assets` / `d1_databases` / `observability` は非継承キーで、
`[env.staging]` 側に再指定しないと引き継がれない（アセット配信や D1 バインディングが
欠落した Worker ができる）。

## 本番の解析データを読む

実データを見るときは **`scripts/analytics-query.sh` を唯一の入口にする**。

```bash
scripts/analytics-query.sh "SELECT kind, COUNT(*) FROM events GROUP BY kind"
scripts/analytics-query.sh --env staging "SELECT COUNT(*) FROM events"
```

`npx wrangler d1 execute --remote` を直接叩かないこと。手元の wrangler 認証は
OAuth で `d1 (write)` を含むため、同じ経路で本番 `events` への UPDATE / DELETE /
DROP が通る。`events` は追記のみでバックアップ運用が無く、一度の事故で計測データを
全損する。

書き込めないことは 3 段で担保している。

| 段 | 担保するもの | 実体 |
| --- | --- | --- |
| 認証 | Cloudflare 側で書き込みが 403 になる | Account / D1 / Read だけの API トークンを必須にする |
| 文面 | 書き込み文をローカルで弾く | `analytics-query.sh` が単一の SELECT / WITH 文のみ許可（`--self-test` で検査自体を確認できる） |
| 経路 | ラッパを迂回させない | `.claude/settings.json` の PreToolUse フックが `d1 execute` を含む Bash を落とす |

マイグレーション適用（`d1 migrations apply` / `npm run migrate:remote`）は別経路で、
このフックの対象外。適用には従来どおり書き込み権限のある認証を使う。

### 読み取り専用トークンの作り方

1. Cloudflare ダッシュボード → My Profile → API Tokens → Create Token →
   Create Custom Token
2. Permissions に **Account / D1 / Read** だけを追加する（他は追加しない）
3. Account Resources を対象アカウントに限定する
4. 発行された値を Keychain に入れる（`-w` を省くと対話入力になり、シェル履歴に
   残らない）

   ```bash
   security add-generic-password -a "$USER" -s befold-d1-readonly -w
   ```

   スクリプトは環境変数 `CLOUDFLARE_D1_READONLY_TOKEN` を先に見て、無ければ
   この Keychain 項目から取る。どちらの形でもリポジトリにはコミットしない。

デプロイ用の `CLOUDFLARE_API_TOKEN`（D1 / Edit を含む）とは別物で、混ぜない。

**D1 / Read だけで `wrangler d1 execute --remote` の SELECT は通る**（2026-08-10 に
本番で実測）。書き込みは D1 の API 側が
`You do not have permission to perform this operation. [code: 7500]` で拒否する
（staging に対する `UPDATE` / `DELETE` / `CREATE TABLE` で実測）。

判定は「文の種類」ではなく「実際に変更が発生するか」で行われている。
`DELETE FROM events WHERE 0` や存在しないテーブルへの `DROP TABLE IF EXISTS` は
成功する（1 行も変更しないため）。**権限だけでは書き込み文の実行そのものは
止まらない**ので、`analytics-query.sh` 側の文面検査を外さないこと。

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

## 日別のユニークアクセス元（利用規模の近似）

`events.visitor_token` は `sha256(ip \0 ua \0 JST 日付)` で、**日ごとに値が変わる**
（`src/lib/visitor.ts`）。日をまたぐ同一人物は追えないが、1 日の中の異なり数は
数えられる。これを母集団別に日次で出したものが「日別のユニークアクセス元」。

- **利用者数そのものではなく近似。** 同じ人でも回線が変われば別々に数える
  （モバイル回線・VPN で過大）、同じ回線・同じ端末構成の複数台は 1 になる
  （NAT の内側で過小）。この限界はダッシュボードの当該節に注記として出す。
  指標名に「アクティブ利用者数」を使わない。
- **母集団を混ぜない。** サイト訪問（`kind='visit'`）はサイトを見に来た人、
  アップデート確認（`kind='update_check'`）はアプリを起動して appcast を取りに来た
  端末で、意味が違う。合算した「ユニーク」はどちらの規模も表さない。
- **チャネルを分ける。** `update_check` は develop（開発機）の比率が高く、混ぜると
  利用者の規模を過大に見積もる。系列は `src/lib/github.ts` の `CHANNELS` から
  生成するので、チャネルを増やせば系列も自動で増える（表示名は
  `Record<Channel, string>` なので、名前を書くまで型で落ちる）。`channel` が
  NULL の行は「チャネル未記録」として残し、どちらにも混ぜない。
- **通算のユニーク利用者数は出さない。** 日次ソルトは追跡しないための意図的な
  設計であり、通算を出すには設計変更（永続的な識別子）が要る。必要と判断したら
  プライバシー方針として ADR を起こす。
- **クエリは増やさない。** 母集団ごとに引かず、日別推移のクエリの SELECT 句へ
  `COUNT(DISTINCT CASE WHEN ... END)` を並べる（`UNIQUE_SOURCE_FILTERS` が述語の
  唯一の定義元）。母集団ごとに 1 本ずつ引く形へ戻すと `test/query-count.test.ts`
  の上限で落ちる。
- **ボット除外は他の集計と同じ `HUMAN_ONLY`。** ただし curl のような自動アクセスは
  ボット判定に当たらずここに残る（近似の精度に効くので注記に書いてある）。

## ページとブラウザ言語設定の記録

<!-- constrained-by ../docs/superpowers/specs/2026-07-28-cloudflare-distribution-analytics-design.md -->

`visit` を LP だけでなく `/features` でも計上する。ページの区別は `events.page`、
リクエスト元の言語設定は `events.browser_lang` に持つ。

- **`page` は生パスではなく計上対象ページの列挙**（`src/schema.ts` の `pageSchema`）。
  ルート側が明示して渡す（`recordEvent(c, { kind: 'visit', page: '/features' })`）。
  リクエスト URL から導出しない——`/dl/:tag/:file` のようにパラメータを含む経路が
  あり、導出にすると内訳のカーディナリティが発散するため。
- **`page` が NULL の行には 2 つの意味がある。** 列の導入前に記録された `visit`
  （当時計上していたのは LP だけなので `/` と読んでよい）と、ページの概念が無い
  `download` / `update_check`。このため `COALESCE(page, '/')` は
  `kind = 'visit'` と同じ条件節の中でしか使えない。`src/analytics.ts` の
  `metricExpression` が両者を必ず一緒に組み立てる形になっている。
- **「ページアクセス」指標は `page = '/'` のまま**。LP からの新規獲得を測る系列
  なので、`/features` を足して薄めない。ページ別の内訳は別系列として出す。
  述語は `METRIC_FILTERS` 1 箇所から組み立て、累計・当日・日次・時間帯・内訳が
  それを共有する（同期漏れは `test/analytics.test.ts` の「ページの分離」が検知する）。
- **日次ユニーク訪問者（`COUNT(DISTINCT visitor_token)`）はページで絞らない。**
  「何人来たか」を測るものなので、LP に絞ると `/features` へ直接来た訪問者が
  数から消える。国別・参照元別・UA 内訳の母集団も同様に `/features` を含む。
- **`/features` は `Cache-Control: no-store`。** キャッシュに載った応答は Worker を
  通らず計上できない。ヘッダを単に外すのでは足りない（Cache-Control も Expires も
  無い 200 応答はブラウザのヒューリスティックキャッシュに載り得る）。

### 言語ごとの URL

<!-- constrained-by ../docs/adr/0007-distribution-site-custom-domain.md -->

LP と詳細ページは言語ごとに URL を分ける（日本語 = `/` `/features`、英語 =
`/en` `/en/features`）。かつては日英の本文を同一 HTML に入れて `hidden` の
付け外しで切り替えていたが、その形だと hreflang が原理的に出せず、実際に読まれた
言語もサーバから観測できなかった。**URL が表示言語の唯一の状態**で、`localStorage`
による切替は廃止した。

- **ページの列挙は `src/lib/pages.ts` の `SITE_PAGES` が唯一の定義。** ここから
  ルート登録・`REDIRECTED_PATHS`・sitemap.xml・hreflang・`og:locale` の 5 つを
  導出する。5 箇所に書き写す形は必ずどこかが取り残される（ADR 0007 の決定 2 自身が
  「列挙は漏れる形で壊れる」と書いている）。
- **`SITE_PAGES` に機械向けの経路を載せてはならない。** この表は「旧ホストから
  新ドメインへ 301 してよい HTML ページ」でもあるため、appcast・`/dl/`・`/download`
  を載せると出荷済みアプリの更新経路や LP 由来のダウンロード計測が壊れる
  （ADR 0007 の決定 2）。旧ホストの `/download` が 301 されないことは
  `test/public.test.ts` が検査している。
- **hreflang は自己参照を含む全バリアントを各ページに置く。** 検索エンジンは
  「各版が自分自身を含む全版を相互に指す」ことを対応関係の成立条件にしており、
  自己参照を落とすと対応が成立しない。sitemap の `xhtml:link` も同じ集合。
- **`x-default` は置かない。** Accept-Language で振り分ける入口ページを作って
  いないので、指すべき既定版が無い。
- **Accept-Language による自動リダイレクトはしない。** クローラは Accept-Language を
  送らない（送っても代表的でない）ため、自動リダイレクトは「英語ページが
  クロールされない」「日本語ページが英語圏で見られない」のどちらかに倒れる。
  加えて `Vary: Accept-Language` が要り、中間キャッシュとの相互作用が読めなくなる。
  相手言語への導線はヘッダの `<a>` リンクで常設する。
- **4 ルートすべてに `Cache-Control: no-store` を付ける。** 1 本でもキャッシュに
  載ると、そのページの計測だけが環境依存で欠けて日英比率が歪む。
- **JSON-LD はページの言語に合わせる。** 構造化データの文面はページ上に見えて
  いる必要があり、日本語ページに英語の FAQ 本文は存在しないため。

### 404 ページ

ルートにも静的アセットにも当たらないパスは、LP と同じ意匠の 404 ページを
`src/views/not-found.tsx` が返す（`app.notFound`）。

- **判定は「`ASSETS.fetch` が 404 を返したか」で行う。** 先に自前の 404 を返す形に
  すると `/style.css` や `/images/*` が配信されなくなる。パスの形（拡張子の有無・
  `/en` 接頭辞）から推測もしない。
- **日英を 1 枚に併記し、両方の入口へのリンクを置く。** 404 に来たパスは定義上
  `SITE_PAGES` に無く、そこから言語を決められない（`/en` の打ち間違いも
  `/features` の打ち間違いも同じ経路に来る）。宛先は `pathFor` から導出する。
- **`PageShell` を使わず canonical と hreflang を出さない。** 存在しない URL を
  正規化してはならず、言語版の対応関係も主張できない。代わりに `noindex` を付ける。
- **`events` には一切記録しない**（`visit` にしないだけでなく新しい kind も足さない）。
  404 の到達数が要るようになったら Workers Observability で見る。
- **`Cache-Control: no-store`。** あとでそのパスが実在のページになったとき、中間
  キャッシュに残った 404 が返り続けるのを避ける。
- 旧ホストの `/dashboard` はここへ来ない（`routes/dashboard.tsx` が確定的に 404 を
  返す）。人間向けのページではないので素の text のままでよい。

### `browser_lang` と `display_lang`

`Accept-Language` の第一タグを `ja` / `en` / `other` に丸めた値
（`src/lib/lang.ts` の `summarizeLang`）。**これはブラウザの言語設定であって、
実際に読まれた言語ではない。** LP は日英を同一 HTML に持ち、`localStorage` の
`befold-lang` が未設定なら常に日本語を表示する（`src/views/shared.tsx` の
`LANG_SCRIPT`）ため、`en` 設定の初回訪問者も画面では日本語を読んでいる。

この値が答えるのは「英語を求めて来た人がどれだけ居るか」であって
「英語で読んだ人の数」ではない。表示言語そのものを測るには言語ごとに URL を
分ける必要があり、それは LP 多言語化の設計判断として別に扱う。

`Accept-Language` を送らないクライアント（Sparkle）では NULL になる。言語の内訳を
出すときは `kind = 'visit'` で絞ること。全 kind 横断だと `update_check` の NULL が
支配して読めなくなる。

`display_lang` は**実際に配信したページの言語**。値は配信したビューの言語その
もので、URL 文字列からは導出しない（`SITE_PAGES` の該当エントリの `lang` を
ルートがそのまま渡す）。これにより `<html lang>` / hreflang / `og:locale` /
`display_lang` の 4 者が必ず同じ値から出る。

2 つは対で読む。`browser_lang` が「求めた言語」、`display_lang` が「実際に出した
言語」で、両方あって初めて「英語を求めて来た人が英語ページへ辿り着けたか」が
測れる。`display_lang` の NULL も `page` と同じく二義（列の導入前の visit と、
ページの概念が無い `download` / `update_check`）なので、`COALESCE` は
`kind = 'visit'` と同じ条件節の中でのみ使う。

### ダッシュボードのページ別・言語別の内訳

ページ別・表示言語別・ブラウザ言語設定別の 3 つの内訳を、人間とロボットに分けて
出す（`eventBreakdowns`）。

- **クエリは 1 本。** 軸ごとに引くと全表スキャンが 3 本並ぶが、visit の行を
  3 列の組で集約すれば結果は高々数十行にしかならず、軸ごとの集計は TS 側で畳める。
  `summarize` の発行本数には上限テスト（`test/query-count.test.ts`）があり、
  軸ごとに 1 本ずつ引く形へ戻すと落ちる。
- **判定は `NON_HUMAN_MATCH` をそのまま使う。** 人間側と自動アクセス側の両方を
  数えるので `HUMAN_ONLY` は使えないが、判定式そのものは 1 箇所のまま
  （`trafficSplit` と同じ形）。`ua_summary LIKE 'bot:%'` のリテラルと
  `datacenterOrgMatch()` の呼び出しがそれぞれ 1 箇所であることは
  `test/analytics.test.ts` の構造ガードが検査する。
- **ページ別は `page='/'` の「ページアクセス」指標とは別物**で、合計は一致しない。
  日本語 LP と英語 LP はどちらも `page='/'` で、言語は別の軸として出す。
- **最新イベント表の SELECT 句は `RECENT_COLUMNS` で共有する。** `recentEvents`
  （初期表示）と `eventsAfter`（SSE）は同じ `RecentEvent` を返す契約だが、
  `.all<RecentEvent>()` のジェネリクスは実際の列を検査しない。片方から列を落としても
  コンパイルは通り、初期表示にはあるのに SSE で流れる行にだけ列が無い、という形で
  静かに壊れる（実測で確認した）。

## リクエスト先ホストと GitHub フォールバックの記録

<!-- constrained-by ../docs/adr/0007-distribution-site-custom-domain.md -->

配布サイトは 3 世代の URL すべてで応答している（GitHub Pages / `befold.tommy109.workers.dev` /
`befold.degino.com`）。旧世代を止めてよいかは「旧ホストを叩くクライアントがゼロか」で
決まる（ADR 0007 の決定 1）。それを観測するために `events.host` と `events.fallback` を持つ。

- **`host` は全 kind で値を持つ。** `recordEvent` がリクエスト URL から一括で導出し
  （`src/events.ts`）、`EventAttributes` には**含めていない**。経路ごとに渡す形にすると、
  記録箇所を足したときの付け忘れが「その経路だけホスト不明」という静かな欠測になる。
- **値は既知ホスト名そのものか `other`。** 分類は `src/lib/hosts.ts` の `classifyHost` で、
  ホスト名リテラルはそのファイルだけに置く（同決定 6）。生の Host ヘッダは任意の値を
  送れるので、そのまま列へ入れるとカーディナリティが発散する。
- **旧ホストの HTML ページは 301 するので `visit` にならない。** 301 は
  `legacy_redirect` として記録する（`src/index.ts`）。`visit` として記録すると、301 を
  追った先の正規ホストでも `visit` が記録され、ページアクセス数が二重に数えられる。
  機械向けの経路（appcast・`/dl/`・`/download`）は 301 せず素通しなので、旧ホストの
  ままホスト別に出る——ADR 0007 の停止条件が見ているのはこちら。
- **記録されないギャップが 3 つある。** 旧ホストの静的アセット（`notFound` →
  `ASSETS.fetch`）と `/healthz`、そして 404 ページ。前 2 つはクライアントの依存を
  示さないため、404 は LP の指標へ混ぜないために追っていない。
- **`fallback` は R2 ミスで GitHub へ落ちた経路。** `appcast` / `dmg` / `release-api` の
  3 つで、`kind='github_fallback'` のときだけ非 NULL。この対応は `eventSchema` の
  `refine` が強制する（doc コメントだけでは守られない）。ここが 0 でないうちは GitHub
  側の経路を止められない。
- **appcast のフォールバックは過小に出る。** 応答は `caches.default` に 300 秒入るため、
  キャッシュに当たった周期は `loadAppcast` を通らない。`update_check` 自体はキャッシュ
  判定より前に記録するので影響を受けない。

### 新しい kind の行き先を決めさせる

`github_fallback` / `legacy_redirect` は製品の指標ではなく運用の観測なので、カード・
グラフの系列（`KIND_LABELS`）には出さず `OPERATIONAL_KINDS` に入れて専用セクションで
見る。`test/analytics.test.ts` が「全 kind が `KIND_LABELS` か `OPERATIONAL_KINDS` の
どちらかに含まれる」ことを検査するので、kind を足したらどちらにするかを必ず決めることになる
（記録だけされて画面のどこにも出ない、という状態を作らせない）。

### ホスト別は 0 件の行を落とさない

ダッシュボードの他の内訳は 0 件の区分を落とすが、ホスト別は既知ホストを常に並べる。
ここで見たいのは「旧ホストがゼロであること」そのものなので、行が消えると「まだ 0」と
「そもそも計測していない」が区別できなくなる。

### GitHub 直の appcast は Worker では観測できない

v1.10.0 以前のクライアントは `https://github.com/YTommy109/befold/releases/download/appcast/appcast.xml`
を直接見るため、サイトを経由せず Worker には現れない。別手段として GitHub の
Releases API がアセットごとの `download_count` を返す（実測: 2026-08-16 時点で
`appcast.xml` / `appcast-develop.xml` とも 0）。

```bash
curl -s https://api.github.com/repos/YTommy109/befold/releases/tags/appcast \
  | jq '.assets[] | {name, download_count}'
```

ただし**この数はアセットを差し替えるとゼロに戻る**。appcast はリリースのたびに
上書きするので、カウンタは「前回のリリース以降の取得数」しか表さない（上の 0 も、
2026-08-15 に差し替えた直後であることによる）。累計として使うには差し替え前に
スナップショットを取る必要があり、リリースワークフローに計測のための手順を足すことに
なる。**現時点では採らない**——GitHub 直の appcast を見るクライアントは
自動アップデートで新しいバージョンへ移れば Worker 側の `update_check` に現れるため、
Worker 側のホスト別の推移で間接的に追える。

## 人間の訪問と自動アクセスの分離

<!-- constrained-by ../docs/adr/0004-bot-detection-via-user-agent.md -->
<!-- constrained-by ../docs/adr/0008-datacenter-traffic-via-as-org.md -->

JS ビーコンを使わないサーバ側計測なので、クローラの巡回も `visit` として
記録されている。人間の訪問から外すものは**ふたつの軸**で判定する。

| 軸 | 見るもの | 遡及 | ADR |
| --- | --- | --- | --- |
| ロボット | `ua_summary` の `bot:` 接頭辞 | 2026-08-09 以降のみ | 0004 |
| データセンター由来 | `as_org`（接続元組織） | 2026-07-30 以降の全期間 | 0008 |

集計クエリは `analytics.ts` の `HUMAN_ONLY`（= `NOT (BOT_MATCH OR DATACENTER_MATCH)`）
だけを見る。2 軸を OR で束ねる形はそこ以外に書かない——片方だけを見る箇所ができると、
人間側から引かれたぶんが自動アクセス側にも出ず、画面上で総和が合わなくなる。

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

### データセンター由来（接続元組織の軸）

UA はふつうのブラウザだが接続元がクラウド・ホスティング・スキャン業者である
アクセスを分ける（ADR 0008）。UA の軸では人間として数えられていたもので、実測では
本番の visit 372 件のうち 207 件がこれに当たった。

- **判定は記録時ではなく集計時**。`as_org` は記録済みなので、集計時に判定すれば
  過去データにも遡って効く（UA 分類との非対称はダッシュボードの注記に出す）。
- **パターンの定義元は `src/lib/network.ts` の `DATACENTER_ORG_PATTERNS` だけ。**
  SQL 断片は `datacenterOrgMatch()` が同じ配列から生成する。手書きの LIKE 列を
  置くと、パターンを足したときに片方だけ直る（`test/analytics.test.ts` の構造ガードと
  `test/network.test.ts` が検査する）。
- **迷ったら人間側に残す。** プライバシー中継（iCloud Private Relay / WARP の出口＝
  Cloudflare / Akamai / Fastly）、VPN・Tor の出口、消費者向け ISP、`as_org` が NULL の
  行は含めない。人間を少なく見積もると、まだ使われている配布経路を止めてしまう
  （ADR 0007 の停止判断にこの数字を使う）。
- **UA でボットと分かるものが優先。** データセンターから来る Googlebot は「ロボット」に
  数える。「データセンター」へ寄せるとクローラ名の内訳から消えるため。
- 人間側の「接続元組織別」テーブルに見慣れないホスティング事業者が並び始めたら、
  パターン追加のシグナルとして読む。

## ダッシュボードの認証方式

Cloudflare Access（self-hosted アプリケーション）と、Worker 側の JWT 検証の 2 段で
保護する（ADR 0007 の決定 5）。かつては Basic 認証だったが、独自ドメインへ移行して
Access が張れるようになったため撤去した。

保護は 2 段で成り立つ。Access を張っただけでは Worker 自身は素通しのままで、Access を
経由しない経路で無防備になるため、Worker は `Cf-Access-Jwt-Assertion` を必ず検証する
（署名・`aud`・`iss`・`exp` / `nbf` のすべて。`src/lib/access.ts`）。

- **Access アプリケーションは 2 本のパスで作る。** `befold.degino.com/dashboard` と
  `befold.degino.com/dashboard/*` の両方。ワイルドカードは親パスを含まないため、
  `/dashboard/*` だけでは `/dashboard` が保護されない。
- ポリシーは Allow 1 本、`tokutomi@degino.com` のみ。セッション長は 1 週間。
- `ACCESS_TEAM_DOMAIN`（`<team>.cloudflareaccess.com`）と `ACCESS_AUD`（アプリケーションの
  Application Audience タグ）は秘密ではないため `wrangler.toml` の `[vars]` に置く。
  どちらかが空なら 503 で閉じる。
- 旧ホスト（`*.workers.dev`）の `/dashboard` と `/dashboard/*` は 404 を返す。301 で
  新ドメインへ送る形は取らない（保護対象の入口を 2 つに増やさないため）。
- ブラウザは Access のセッション Cookie を同一オリジンの後続リクエストにも送るため、
  ヘッダを設定できない `EventSource`（SSE）もそのまま動作する。
