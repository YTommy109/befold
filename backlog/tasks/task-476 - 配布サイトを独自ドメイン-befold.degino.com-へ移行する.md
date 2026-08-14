---
id: TASK-476
title: 配布サイトを独自ドメイン befold.degino.com へ移行する
status: Done
assignee: []
created_date: '2026-08-13 14:19'
updated_date: '2026-08-14 07:49'
labels:
  - site
dependencies: []
priority: high
type: task
ordinal: 101000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
DNS 管理を Cloudflare へ集約したため、配布サイト Worker を workers.dev から独自ドメイン befold.degino.com で公開する。

現状（実測）:
- 本番 `befold` / staging `befold-staging` はともに `workers_dev = true` のみで公開（site/wrangler.toml）。独自ドメインを使わない理由がコメントに明記されている（Access が張れないため Basic 認証）。
- 出荷済みアプリの Sparkle フィードは `https://befold.tommy109.workers.dev/appcast{,-develop}.xml` にハードコードされている（BefoldApp/befold/Updates/UpdateChannel.swift:21,23）。過去リリースの appcast enclosure も `https://befold.tommy109.workers.dev/dl/<tag>/`（.github/workflows/release.yml:274）。
- アプリ内リンクは AppLinks.homepage / .help（BefoldApp/BefoldKit/AppLinks.swift）。
- サイト側の絶対 URL は原則リクエスト origin 由来だが、DOWNLOAD_URL は定数（site/src/views/shared.tsx:13）、自己参照判定 selfHost は単一ホスト前提（site/src/lib/referrer.ts）。

最重要の制約: 既存ユーザーの更新経路を壊さないこと。workers.dev のホスト名は当面停止せず、appcast と /dl/ は新旧どちらのホストでも同じ内容を返し続ける必要がある。

本タスクは束ねるだけで、実作業はサブタスクで行う。
<!-- SECTION:DESCRIPTION:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-476.1 で ADR 0007（`docs/adr/0007-distribution-site-custom-domain.md`、backlog decision-7）を作成し、6 つの判断を確定した。

1. workers.dev は恒久維持・全パス（パス選別しない）
2. 旧ホストのリダイレクトは LP と /features のみの肯定列挙。/download は送らない
3. アプリの appcast URL とリリースの enclosure prefix は新ドメインへ切り替える（理由は可搬性）
4. staging は staging.befold.degino.com
5. ダッシュボードは Access へ移し、旧ホストの /dashboard は 404（保護面を 1 つに畳む）
6. 自己参照の除外を単一ホストから自己ホスト集合へ変える（移行と同じデプロイに入れる）

サブタスク 476.2〜476.6 の Description / Acceptance Criteria はこの決定に合わせて更新済み。

サブタスク 476.1〜476.6 をすべて完了。配布サイトは独自ドメイン befold.degino.com で
公開され、旧ホスト befold.tommy109.workers.dev は恒久併存（appcast と /dl/ が応答し続ける）。
ダッシュボードは Cloudflare Access + Worker 側 JWT 検証の 2 段で保護し、旧ホストでは 404。

最終確認（2026-08-14、本番）:

| URL | 結果 |
| --- | --- |
| `befold.degino.com/dashboard` | 未認証 302 → Access、認証後 200 |
| `befold.degino.com/dashboard/stream` | 未認証 302 → Access、認証後 SSE 確立 |
| `befold.tommy109.workers.dev/dashboard{,/stream}` | 404 |
| `befold.degino.com/` `/download` `/appcast.xml` | 200 |
| `befold.tommy109.workers.dev/appcast.xml` | 200（更新経路は無影響） |
<!-- SECTION:NOTES:END -->
