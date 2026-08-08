---
id: TASK-364
title: staging へのマイグレーション適用とデプロイをワークフロー化する
status: To Do
assignee: []
created_date: '2026-08-08 08:09'
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
- [ ] #1 staging へのマイグレーション適用と Worker デプロイが、手作業の記憶に頼らず実行できる
- [ ] #2 適用とデプロイの順序（マイグレーションが先）が仕組みとして保証されている
- [ ] #3 staging に未適用のマイグレーションが溜まった状態に気づける
- [ ] #4 本番の自動デプロイ経路（site.yml の deploy）と破壊的マイグレーションの歯止めが、この変更で迂回されていない
- [ ] #5 site/README.md の staging 環境の節が新しい手順に更新されている
<!-- AC:END -->
