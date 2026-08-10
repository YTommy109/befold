---
id: TASK-402
title: 解析用 D1 の読み取り専用トークンを発行して write が Cloudflare 側で弾かれることを実測する
status: To Do
assignee: []
created_date: '2026-08-10 01:19'
labels: []
dependencies: []
priority: high
ordinal: 654000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-395 で、解析用 D1 への読み取り経路を scripts/analytics-query.sh の 1 本に畳み、ラッパの SQL 検査・PreToolUse フック・pre-commit の self-test で書き込みを塞いだ。ただし 3 段のうち「認証」の段——Account / D1 / Read だけの API トークンを使い Cloudflare 側で write を 403 にする段——だけが未導入で、人間がターミナルで直接 wrangler を叩く経路は依然 d1 (write) を持つ OAuth 認証を使える。

ラッパはトークンを必須にする実装が既に入っており（環境変数 CLOUDFLARE_D1_READONLY_TOKEN、無ければ Keychain の befold-d1-readonly）、トークンを登録すれば追加のコード変更なしにこの段が有効になる。手順は site/README.md「本番の解析データを読む」に記載済み。

未確認の前提: Account / D1 / Read だけのトークンで wrangler d1 execute --remote が通るか。この経路は POST /accounts/{id}/d1/database/{id}/query を使い、Cloudflare docs は D1 Read / D1 Edit の存在は明記するが /query がどちらに属するかを書いていない。実トークンでの SELECT 1 回でしか判定できない。通らない場合は、Worker 側に読み取り専用の解析エンドポイントを置く案（既存の Basic 認証を流用）へ切り替える。

トークン発行はダッシュボード操作のため、ユーザーが実施する必要がある。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 Account / D1 / Read だけのトークンが発行され、Keychain（befold-d1-readonly）または環境変数として登録されている
- [ ] #2 scripts/analytics-query.sh 経由の SELECT が本番 D1 に対して成功することを実測で確認している
- [ ] #3 そのトークンでは書き込みが Cloudflare 側で拒否されることを、staging に対する書き込みの試行で実測している（本番では試さない）
- [ ] #4 D1 Read で /query が通らなかった場合の代替案の判断が Implementation Notes に記録されている
<!-- AC:END -->
