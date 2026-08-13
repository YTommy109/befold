---
id: TASK-476
title: 配布サイトを独自ドメイン befold.degino.com へ移行する
status: To Do
assignee: []
created_date: '2026-08-13 14:19'
labels:
  - site
dependencies: []
priority: high
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
