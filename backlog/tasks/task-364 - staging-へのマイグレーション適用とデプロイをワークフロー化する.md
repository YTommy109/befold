---
id: TASK-364
title: staging へのマイグレーション適用とデプロイをワークフロー化する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-08 08:09'
updated_date: '2026-08-08 08:17'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 625000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
staging は本番と違い、マイグレーション適用も Worker デプロイも完全に手動で、忘れても誰も気づかない。

## 実測（2026-08-08）

TASK-363 で追加した Site Migrate を staging に対して plan 実行したところ、未適用のマイグレーションが 2 件あった。

- 20260730022424_add_as_org.sql（7/30 のもの。約 10 日間当たっていなかった）
- 20260808071500_rename_ts_and_visitor_day.sql

つまり staging へのマイグレーション適用は、意識して実行しない限り抜ける運用になっている。本番は main へのマージで .github/workflows/site.yml の deploy ジョブが自動適用するため、この非対称性に気づく機会が無い。

## 問題の本質

staging は『本番にしか存在しない条件（実 D1・シークレット・マイグレーション適用順序）を、本番データを汚さずに確認する環境』として置かれている（site/README.md『staging 環境』）。その staging 自体が本番と違う手順で運用されていると、確認したい条件を再現できない。

さらに、スキーマとコードの版がずれた状態が放置されると危険度が上がる。マイグレーションだけ当たって Worker が古いと、旧コードの INSERT がカラム不足で失敗し、insertEvent は例外を飲む設計のため計測が無言で欠落する（今回まさにその状態を一時的に作った）。

## 検討する案

1. staging デプロイもワークフロー化し、マイグレーション適用とセットで実行する（マイグレーション → デプロイ の順序を CI に固定する。本番の deploy ジョブと同じ考え方）
2. Site Migrate を schedule で staging に plan だけ流し、未適用があれば気づけるようにする（軽いが、気づいた後の作業は手動のまま）

案 1 のほうが根本的。着手時にどちらを採るか決めること。案 1 を採る場合、本番の deploy ジョブと同じ concurrency group（site-deploy）に入れるかどうかも判断する（staging と本番は別リソースなので分けてよい可能性が高い）。

## 前提（未確認）

staging の Worker が現在どのコミットのコードで動いているかは確認していない。2026-08-08 時点でスキーマだけ新しく、Worker は古い可能性がある。着手時に wrangler deployments list --env staging 等で確認すること。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 staging へのマイグレーション適用と Worker デプロイが、手作業の記憶に頼らず実行できる
- [x] #2 適用とデプロイの順序（マイグレーションが先）が仕組みとして保証されている
- [x] #3 staging に未適用のマイグレーションが溜まった状態に気づける
- [x] #4 本番の自動デプロイ経路（site.yml の deploy）と破壊的マイグレーションの歯止めが、この変更で迂回されていない
- [x] #5 site/README.md の staging 環境の節が新しい手順に更新されている
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. 案1を採る。新規 .github/workflows/site-staging.yml を追加し、workflow_dispatch（ブランチ選択）で typecheck/test → migrate:staging → deploy:staging の順に固定する。
2. AC#3 は同ワークフローの schedule（週次 cron）ジョブで担保する。staging の未適用マイグレーションを列挙し、1件でもあればジョブを失敗させる（読み取りのみ、自動適用はしない）。
3. 未適用判定を scripts/lib/d1-pending-migrations.sh へ抽出し、check-destructive-migrations.sh と新規 check-pending-migrations.sh の両方から使う（同じ判定を二重実装しない）。--env 対応を追加して staging DB も扱えるようにする。
4. site.yml は deploy の実行時依存が増えるため on.paths に lib スクリプトを追加するのみ。歯止め（check-destructive-migrations.sh）と production 経路のステップ構成は変更しない（AC#4）。
5. staging では破壊的ガードを回さない。staging データは使い捨てで、破壊的マイグレーションの本番前リハーサル場として当てられる必要があるため。この判断は README とワークフローのコメントに残す。
6. site/README.md の『staging 環境』節を新手順（Site Staging Deploy ワークフロー）に更新する。
7. actionlint / markdownlint / shellcheck で検証する。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
採用: 案1（staging デプロイもワークフロー化）+ 案2（drift 検知）の併用。トリガーは workflow_dispatch のみ、drift は週次 schedule（ユーザー判断）。

## 判断と根拠

- **トリガーを workflow_dispatch のみにした**: staging は『main へマージする前に任意のブランチを実 D1 で確認する』場（site/README.md『staging 環境』）。main push で自動化すると staging が常に本番と同版になり、マージ前検証という存在意義が失われる。
- **staging では破壊的ガード（check-destructive-migrations.sh）を回さない**: staging のデータは使い捨てで、DROP/RENAME を含むマイグレーションを本番より先に当てて確かめるための環境。歯止めが要るのは取り返しのつかない本番データのほう。site.yml 側はそのまま。
- **concurrency は site-staging-deploy と別グループ**: staging と本番は Worker も D1 も別リソースで互いを待つ理由がない。staging 同士は直列（版の食い違い防止）。
- **drift は検知のみで自動適用しない**: スキーマだけ進んでコードが古い状態はまさに本タスクが問題視した状態であり、CI 自身がそれを作ってはならない。
- **未適用判定を scripts/lib/d1-pending-migrations.sh へ抽出**: check-destructive-migrations.sh と新規 check-pending-migrations.sh で『何が未適用か』を二重実装すると片方だけ直したときに見えるものがずれるため一本化。--env 対応を追加して staging DB も扱えるようにした。site.yml の on.paths に lib を追加（deploy の実行時依存。TASK-197 で paths 漏れによりワークフローが起動しなかった前例がある）。

## 検証

- actionlint: エラーなし（site-staging.yml / site.yml）
- markdownlint-cli2: 65 files, 0 issues
- スクリプトは npx をスタブして実測。全 7 ケースで期待どおり:
  - 全適用済み → pending/destructive とも exit 0
  - 全未適用 → pending exit 1、4 件を列挙
  - RENAME 未適用 → destructive exit 1、『破壊的な文を検出』
  - d1_migrations 不在 → 全件未適用として扱い exit 1
  - 認証失敗 → pending/destructive とも exit 1 で理由を stderr へ（プロセス置換をやめて変数受けにし、失敗が while の終了ステータスに埋もれる回帰を防いだ）
  - --env staging 指定時の実引数: wrangler d1 execute befold-analytics-staging --remote --env staging --json ...
  - 本番（--env 無し）でも macOS bash 3.2 の set -u で落ちないことを確認（空配列展開を ${a[@]+...} で保護）
- 破壊的ガードの本番挙動は上記マトリクスで変更前と一致。site.yml の差分は on.paths への 2 行追加のみ（歯止めのステップ構成は無変更）。

## マージ後に確認すること

workflow_dispatch と schedule はデフォルトブランチ（main）にワークフローが存在して初めて有効になるため、実行そのものは未確認。マージ後に gh workflow run site-staging.yml で 1 回回し、TASK-364 で検出済みの staging 未適用 2 件が解消することと Worker が最新コミットになることを確認する。

## 前提（未確認のまま）

staging の Worker が現在どのコミットで動いているかは確認していない（wrangler の認証がこの環境で通らないため）。マージ後の初回実行で最新に揃うので、確認せずに進めた。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
staging への反映を Site Staging ワークフロー（.github/workflows/site-staging.yml）に集約した。workflow_dispatch で型チェック → テスト → migrate:staging → deploy:staging の順に固定し、順序を手順の記憶ではなくステップ順で保証する。同ワークフローの週次 schedule ジョブが scripts/check-pending-migrations.sh で staging の未適用マイグレーションを検知し、1 件でもあればジョブを失敗させる（適用はしない）。未適用判定は scripts/lib/d1-pending-migrations.sh へ抽出して既存の破壊的ガードと共有した。本番の site.yml は on.paths への 2 行追加のみで、破壊的マイグレーションの歯止めは無変更。actionlint / markdownlint はエラーなし、スクリプトは wrangler をスタブして 7 ケースを実測。ワークフローの実行自体はマージ後に確認する。
<!-- SECTION:FINAL_SUMMARY:END -->
