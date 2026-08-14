---
id: decision-7
title: 配布サイトを独自ドメイン befold.degino.com へ移し workers.dev を恒久併存させる
date: '2026-08-14 06:14'
status: accepted
---
## Context

本決定の記録は `docs/adr/0007-distribution-site-custom-domain.md` にある。
実測値・トレードオフ・担保の一覧はすべて ADR 側を参照すること。
実装タスクは TASK-476（サブタスク 476.1〜476.6）。

## Decision

配布サイト Worker を `befold.degino.com` の Custom Domain で公開し、
既存の `*.workers.dev` ホストは停止せず恒久的に併存させる。

旧ホストを止められないのは、出荷済みアプリの Sparkle フィード URL
（`BefoldApp/befold/Updates/UpdateChannel.swift:21,23`）と、配信済み appcast の
enclosure URL（`.github/workflows/release.yml:274` が組む `/dl/<tag>/`）が
どちらも後から変更できないため。旧ホストではパスを選別せず全パスを維持する。

旧ホストからのリダイレクトは LP と `/features` のみを対象とする肯定列挙で行い、
「appcast と `/dl/` を除く」という否定列挙は取らない（列挙漏れが安全側に倒れるため）。

ダッシュボードは Cloudflare Access へ移し、保護面を新ドメインの 1 つに畳む
（旧ホストの `/dashboard` は 404）。「workers.dev には Access を設定できない」という
現行コード中の前提（`site/wrangler.toml:7`、`site/src/routes/dashboard.tsx:16`）は
現在の Cloudflare ドキュメントに照らして誤りだが、保護面を増やさない判断は変えない。

## Consequences

旧ホストは無期限に生き続けるため、Worker のルーティングとテストは常に
2 ホストを前提にする。自己参照の除外は単一ホスト前提
（`site/src/lib/referrer.ts:44`）から自己ホスト集合へ変える必要があり、
これを移行と同じデプロイに入れないと計測データに断層が残る。
