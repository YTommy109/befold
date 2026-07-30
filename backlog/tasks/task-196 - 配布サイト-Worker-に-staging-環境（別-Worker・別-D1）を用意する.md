---
id: TASK-196
title: 配布サイト Worker に staging 環境（別 Worker・別 D1）を用意する
status: To Do
assignee: []
created_date: '2026-07-30 00:06'
labels: []
dependencies: []
priority: medium
ordinal: 279000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
本番の D1（befold-analytics）に動作確認由来のイベントが混入した実害が発生した（2026-07-30、referrer='verify-param' 等 2 行をユーザーが手動削除）。ローカル dev 用 D1 と vitest 用 D1 は既に分離されているが、シークレット・バインディング・実 D1・マイグレーション適用順序といった『本番にしか存在しない条件』を確認する手段が本番しかなく、確認のたびに本番の分析データが汚れる。

wrangler.toml に [env.staging] を追加し、別名 Worker（befold-staging）と別 D1（befold-analytics-staging）を用意する。デプロイ後の疎通確認は staging で行い、本番への確認は記録が走っても意味を持つもの（appcast の byte 一致など）に絞れる状態にする。

注意: Preview URL（wrangler versions upload --preview-alias）ではデータ分離できない。バインディングは wrangler.toml のものが使われるため、プレビュー URL でも書き込み先は本番 D1 になる。環境を分ける以外に手段がない。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 wrangler deploy --env staging で本番とは別 URL の Worker が公開される
- [ ] #2 staging の Worker は本番とは別の D1 に書き込み、本番の events テーブルに影響しない
- [ ] #3 staging でもダッシュボードの Basic 認証が機能する（シークレットが環境ごとに登録されている）
- [ ] #4 site/README.md に staging の用途とデプロイ手順が記載される
<!-- AC:END -->
