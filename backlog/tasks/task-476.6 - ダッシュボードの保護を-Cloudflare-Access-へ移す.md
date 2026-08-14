---
id: TASK-476.6
title: ダッシュボードの保護を Cloudflare Access へ移す
status: In Progress
assignee: []
created_date: '2026-08-13 14:21'
updated_date: '2026-08-14 07:44'
labels:
  - site
dependencies:
  - TASK-476.1
  - TASK-476.2
  - TASK-476.3
parent_task_id: TASK-476
priority: low
type: chore
ordinal: 101600
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
独自ドメイン配下になることで Cloudflare Access が使えるようになる。ADR 0007 の決定 5 で「Access へ移す」と確定済み（本タスクの実施は確定。条件付きではない）。

<!-- constrained-by ../../docs/adr/0007-distribution-site-custom-domain.md -->

現状は Worker 側の Basic 認証（シークレット DASHBOARD_PASSWORD）で保護している（`site/src/routes/dashboard.tsx:13-29`）。設定ファイルとコード中のコメントは「workers.dev には Access を張れない」を根拠に挙げているが、この前提は現在の Cloudflare ドキュメントに照らして誤り。それでも保護面は新ドメインの 1 つに畳む（2 面あると片方だけ設定が抜ける形で破れる）。

実装:
- 新ドメインの `/dashboard` と `/dashboard/*` を Access の self-hosted アプリケーションで保護する。**ワイルドカードは親パスを含まないため 2 本の指定が必要**（Cloudflare「Access application paths」）。
- Worker 側で Access の JWT（`Cf-Access-Jwt-Assertion`）を検証する。Access を張っても Worker が素通しでは、経路を迂回された場合に無防備になる。
- **旧ホスト（workers.dev）の `/dashboard` は 404 を返す。** 301 で新ドメインへ送る形は取らない（ダッシュボードは新ドメイン専用とする）。
- Basic 認証は Access の動作を実測で確認するまで残し、確認後に削除する。`DASHBOARD_PASSWORD` シークレットも同時に削除する。
- SSE（`site/src/routes/dashboard.tsx:37-96` の `/dashboard/stream`）が Access 経由で動くことを実測で確認する。

未確定: Access のポリシー内容（許可する識別子・セッション長）は本タスクで決める。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 新ドメインの /dashboard が Access で保護され、認証後に集計と SSE が従来どおり動作する
- [ ] #2 /dashboard と /dashboard/* の両方が保護されている（親パスがワイルドカードから漏れていない）
- [ ] #3 Worker 側で Access JWT を検証しており、JWT 未提示のリクエストが通らない
- [ ] #4 旧ホストの /dashboard が 404 を返す
- [ ] #5 Basic 認証の実装・DASHBOARD_PASSWORD シークレット・テスト・ドキュメントの記述が整理されている
- [ ] #6 Access のポリシー内容（許可する識別子・セッション長）が Implementation Notes に記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## コード側（実装済み・commit 2a76c6b9）

- `site/src/lib/access.ts` を追加。`Cf-Access-Jwt-Assertion` を RS256 で検証し、
  署名・`aud`・`iss`・`exp`/`nbf` をすべて見る。JWKS は team domain ごとに 1 時間
  キャッシュし、未知の kid が来たら期限前でも取り直す（鍵回転で全落ちしないため）。
- `site/src/routes/dashboard.tsx` の Basic 認証を撤去し、以下の順で判定する。
  1. 旧ホスト（`LEGACY_HOST` / `LEGACY_STAGING_HOST`）→ 確定的に 404
  2. `ACCESS_TEAM_DOMAIN` / `ACCESS_AUD` が空 → 503（ただしホストが localhost の
     ときだけ素通し。2 条件の積なので、設定済みの本番ではホストに関わらず入らない）
  3. JWT 無し → 401 / 検証失敗 → 403
- `wrangler.toml` に `[vars]` / `[env.staging.vars]` として `ACCESS_TEAM_DOMAIN`・
  `ACCESS_AUD` を宣言（現在は空文字）。秘密ではないので secret ではなく vars。
- テスト: `test/dashboard.test.ts` に Access の describe を新設（実 RSA 鍵ペアを
  生成し JWKS の fetch だけ差し替えて本物の署名を通す）。検証を無効化すると
  4 件が落ちることを実測で確認済み。`test/wrangler-config.test.ts` に vars 宣言の
  ガードを追加。`npx vitest run` は 180 件すべて成功。
- README のダッシュボード節・デプロイ手順・ローカル開発節を Access 前提へ更新。

## ポリシー（AC #6）

- Allow ポリシー 1 本、identity は `tokutomi@degino.com` のみ（Emails）
- セッション長 1 週間（168h）
- アプリケーションは本番・staging それぞれで、パス 2 本
  （`/dashboard` と `/dashboard/*`）。ワイルドカードは親パスを含まないため。

## ブロック中（外部要因）

このアカウントでは **Zero Trust がまだ有効化されていない**。実測: Cloudflare API
`GET /accounts/.../access/organizations` が
`9999 access.api.error.not_enabled: Access is not enabled` を返す。有効化はプラン選択を
伴うためダッシュボード操作が必要で、`POST .../access/organizations` は `10000
Authentication error`（トークンに Access write が無い）。

解消に必要なこと:
1. dash.cloudflare.com → Zero Trust を有効化（Free プラン）し team 名を決める
2. 本番・staging の Access アプリケーションを上のポリシーで作成する
3. team domain と各アプリの AUD タグを共有する

受領後にこちらで行う残作業: `wrangler.toml` の vars を埋める → staging へデプロイ →
`/dashboard` と `/dashboard/stream`（SSE）が Access 経由で動くことを実測 → 本番へ
デプロイ → 旧ホストの 404 を実測 → `DASHBOARD_PASSWORD` / `DASHBOARD_USER`
シークレットを本番・staging から削除。

## staging での実測（2026-08-14、version 52bf410a）

`npx wrangler deploy --env staging` 後の実測（curl の HTTP ステータス）:

| URL | 結果 |
| --- | --- |
| `befold-staging.tommy109.workers.dev/dashboard` | 404 |
| `befold-staging.tommy109.workers.dev/dashboard/stream` | 404 |
| `staging.befold.degino.com/dashboard` | 503 |
| `staging.befold.degino.com/dashboard/stream` | 503 |
| `staging.befold.degino.com/` | 200 |
| `staging.befold.degino.com/healthz` | 200 |

旧ホストの 404（AC #4 の staging 側）と、Access 未設定時に素通しせず閉じることを
確認した。公開ルートには影響していない。AC #1〜#3 は Access アプリケーション作成後に
測る。

Zero Trust 有効化は API から行えないことを再確認した（`POST` / `PUT
/accounts/.../access/organizations` はいずれも `10000 Authentication error`。
一方 `GET /accounts/.../subscriptions` は 200 を返すため、トークンが無効なのではなく
Access の書き込み権限が無い）。

## Access アプリケーション作成（API 実行、2026-08-14）

`Access: Apps and Policies – Edit` のみを持つ API トークンで作成した（作業後にファイル削除。
ユーザー側で revoke 予定）。

| | 本番 | staging |
| --- | --- | --- |
| id | `7a6f1185-3e5f-4e3d-b56a-0f56401176e5` | `4e8328b0-5320-4267-a59f-25d2660294e8` |
| AUD | `f6b3a6db…f38f7` | `e8b98cfd…5d014` |
| hostnames | `befold.degino.com/dashboard` と `/dashboard/*` | `staging.befold.degino.com/dashboard` と `/dashboard/*` |
| session | 168h | 168h |
| policy | allow / Emails=`tokutomi@degino.com` / 168h | 同左 |

team domain は **`degino.cloudflareaccess.com`**。API の
`GET /access/organizations` はリネーム前の `icy-night-33af.cloudflareaccess.com` を
返しており、その値で deploy すると JWKS 取得が 404 になるところだった。
`/cdn-cgi/access/certs` の応答（degino=200 / icy-night-33af=404）と、Access の
ログインリダイレクト先で確定させた。**API の値を鵜呑みにせず実測したことで踏まずに済んだ。**

サービストークンによる無人検証は断念した（トークンに `Access: Service Tokens` が
無く 10000）。結果的に一時的な allow ポリシーを作らずに済んでいる。

## 本番の実測（version ebf99651）

| URL | 結果 |
| --- | --- |
| `befold.degino.com/dashboard` | 302 → `degino.cloudflareaccess.com/cdn-cgi/access/login/…?kid=f6b3a6d…` |
| `befold.degino.com/dashboard/stream` | 302 → 同上（親パスもワイルドカードも保護されている） |
| `befold.tommy109.workers.dev/dashboard` | 404 |
| `befold.tommy109.workers.dev/dashboard/stream` | 404 |
| `befold.degino.com/` | 200 |
| `befold.degino.com/download` | 200 |
| `befold.degino.com/appcast.xml` | 200 |
| `befold.tommy109.workers.dev/appcast.xml` | 200 |

リダイレクト URL の `kid` が本番 AUD と一致しており、両パスが同一アプリで保護されて
いることを確認した（AC #2）。更新経路（appcast・/download）は新旧どちらも無影響。

## シークレット削除（AC #5）

`DASHBOARD_PASSWORD` / `DASHBOARD_USER` を本番から、`DASHBOARD_PASSWORD` を staging から
削除。`wrangler secret list` は両環境とも `[]`。`.dev.vars.example` とコード・テスト・
README からも DASHBOARD 系の記述を除去済み。

## 残り

AC #1 の「認証後に集計と SSE が動作する」はブラウザでの One-time PIN ログインを伴うため
ユーザー確認が必要。
<!-- SECTION:NOTES:END -->
