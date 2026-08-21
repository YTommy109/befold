---
id: TASK-464
title: befold Worker をカスタムドメイン befold.degino.com で公開する
status: To Do
assignee: []
created_date: '2026-08-12 12:19'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 687000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
現在 LP・ダッシュボード・配布（appcast / DMG）を担う Cloudflare Worker `befold` は `https://befold.tommy109.workers.dev/` でのみ公開されている。これを自前ドメイン `befold.degino.com` で公開し、以後の正規 URL とする。

## 前提（2026-08-12 時点で確認済み）

- Cloudflare アカウント: Tokutomi@degino.com's Account (96b3602a71be49f99732550f9f3dedad)
- `degino.com` ゾーンは Cloudflare 上で status=active、NS は tina/tony.ns.cloudflare.com。
  Workers のカスタムドメインの前提（ネームサーバが Cloudflare 管理）を満たす
- カスタムドメインは Worker 全体に張られるため `/` と `/dashboard` で別設定は不要。
  DNS レコードと証明書は Cloudflare が自動生成するので手動の CNAME 追加は不要
- 同一 Worker（name = "befold"）にドメインを足すだけなので、D1 / R2 / シークレットの
  移行は発生しない（`site/wrangler.toml`）

## 壊してはならないもの

- `degino.com` の MX（aspmx.l.google.com ほか計 5 本、Google Workspace のメール）
- apex と `www` の GitLab Pages 配信

## 調査で判明した事実（サブタスクの根拠）

- `site/wrangler.toml` には `routes` / `custom_domain` の定義が一切なく `workers_dev = true` のみ
- 絶対 URL のハードコードは `site/src/views/shared.tsx:13`（DOWNLOAD_URL）、
  `BefoldApp/befold/Updates/UpdateChannel.swift:21,23`（Sparkle フィード）、
  `BefoldApp/BefoldKit/AppLinks.swift:10,15`、`.github/workflows/release.yml:274`
  （appcast enclosure の download_url_prefix）、`docs/index.html`、各種 README / テスト
- OAuth は不使用。認証は `/dashboard` の Basic 認証のみ（`site/src/routes/dashboard.tsx:21-29`）で、
  外部サービスへのコールバック URL 登録は不要
- Cookie / セッションは未使用（訪問者識別は IP+UA のハッシュ）。ドメイン変更で失われる状態は無い
- CORS / CSP ヘッダの設定は無い
- sitemap / robots / canonical / OG は `new URL(c.req.url).origin` 由来で自動追従する
- 既存 appcast の過去エントリは旧 URL のまま残る（generate_appcast の仕様）。
  出荷済みアプリも旧フィード URL を叩き続けるため、`befold.tommy109.workers.dev` は
  当面生かし続ける必要がある

## 論点（サブタスクで決める）

- staging（`befold-staging`）にもカスタムドメインを割り当てるか
- 移行後に `workers_dev = false` にするか（旧 URL の自動更新経路と衝突する）
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 https://befold.degino.com/ で LP が、/dashboard でダッシュボードが表示される
- [ ] #2 https://befold.degino.com/appcast.xml と /download が本番と同じ内容を返す
- [ ] #3 degino.com の MX レコードと apex / www の GitLab Pages 配信が変更前と同一である
- [ ] #4 既存ユーザーの自動更新経路（旧 workers.dev の appcast / dl）が引き続き動作する
- [ ] #5 staging の扱いと workers_dev の無効化可否がサブタスクで明示的に決定され、記録されている
<!-- AC:END -->
