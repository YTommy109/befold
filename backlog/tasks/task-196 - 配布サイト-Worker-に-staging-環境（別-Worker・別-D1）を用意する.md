---
id: TASK-196
title: 配布サイト Worker に staging 環境（別 Worker・別 D1）を用意する
status: Done
assignee:
  - '@Tommy109'
created_date: '2026-07-30 00:06'
updated_date: '2026-07-30 01:13'
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
- [x] #1 wrangler deploy --env staging で本番とは別 URL の Worker が公開される
- [x] #2 staging の Worker は本番とは別の D1 に書き込み、本番の events テーブルに影響しない
- [x] #3 staging でもダッシュボードの Basic 認証が機能する（シークレットが環境ごとに登録されている）
- [x] #4 site/README.md に staging の用途とデプロイ手順が記載される
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. wrangler d1 create befold-analytics-staging で staging 用 D1 を作る。
2. wrangler.toml に [env.staging] を追加する。assets / d1_databases / observability は wrangler の非継承キーなので env 側に再指定する（欠けるとアセット配信や D1 バインディングが無い Worker になる）。
3. package.json に deploy:staging と migrate:staging を追加し、本番と同じ「マイグレーション → デプロイ」の順序を script として固定する。
4. deploy --env staging --dry-run でバインディングが staging の D1 を指すことを確認してから適用・デプロイする。
5. 本番のイベント数を事前に記録し、staging へ疎通確認を投げた後で本番が無変化であることを確認して分離を実証する。
6. site/README.md に staging の用途・手順・落とし穴（--env 付け忘れ、Preview URL では分離できない、非継承キー）を記載する。
7. シークレット登録は対話シェルが必要なためユーザーに依頼する（AC#3）。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
wrangler.toml に [env.staging]（name=befold-staging）を追加し、assets / d1_databases / observability を env 側に再指定した。これらは wrangler の非継承キーで、省くとアセット配信や D1 バインディングを持たない Worker ができる。package.json に deploy:staging と migrate:staging を追加。

D1 を新規作成: befold-analytics-staging / id 185c1ea1-3cbf-4b39-8d5e-d94e87a12c30（APAC）。無料枠 10 DB 以内で課金なし。

検証:
#1 https://befold-staging.tommy109.workers.dev で / 200・/download 302・/appcast.xml 200。deploy --env staging --dry-run でバインディングが befold-analytics-staging を指すことを事前確認。
#2 デプロイ前に本番のイベント数 44 を記録し、staging へ疎通確認 5 リクエスト（うち 1 件は ?ref=staging-smoke）を投げた。staging D1 に 5 件記録され、本番は 44 件のまま・referrer='staging-smoke' の混入 0 件。本番設定も deploy --dry-run で befold-analytics を指したままであることを確認。
#3 シークレット登録前は /dashboard と /dashboard/stream がともに 503、登録後は 401 に変化。未設定時 503 は実装の仕様なので、この遷移がシークレットが非空で登録されたことの証跡になる。wrangler secret list の結果は production が DASHBOARD_PASSWORD + DASHBOARD_USER、staging が DASHBOARD_PASSWORD のみで、シークレットが環境ごとに独立していることを確認（--env staging での登録が本番を上書きしていない。本番 /dashboard も 401 のまま）。正しい認証情報での 200 は vitest で担保。
#4 site/README.md に staging セクションを追加。用途・手順・落とし穴（--env 付け忘れで本番を上書きする、Preview URL では分離できない、非継承キーの再指定が必要）を記載。

観測の訂正: デプロイ直後に /dashboard/stream が 404 を返したが、これは伝播中の一時的な値だった。安定後は本番と同じ挙動（未設定時 503 / 設定後 401）で、実装差異はない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
wrangler.toml に [env.staging] を追加し、別 Worker（befold-staging）と別 D1（befold-analytics-staging）による staging 環境を用意した。deploy:staging / migrate:staging を script 化してマイグレーション先行の順序を固定し、README に用途・手順・落とし穴を記載した。分離はデプロイ前後の本番イベント数（44 件で不変）と staging D1 への記録 5 件で実証し、シークレットの環境独立も wrangler secret list と 503→401 の遷移で確認済み。
<!-- SECTION:FINAL_SUMMARY:END -->
