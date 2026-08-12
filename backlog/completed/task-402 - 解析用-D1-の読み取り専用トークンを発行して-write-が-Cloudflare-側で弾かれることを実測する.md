---
id: TASK-402
title: 解析用 D1 の読み取り専用トークンを発行して write が Cloudflare 側で弾かれることを実測する
status: Done
assignee:
  - '@claude'
created_date: '2026-08-10 01:19'
updated_date: '2026-08-10 01:22'
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
- [x] #1 Account / D1 / Read だけのトークンが発行され、Keychain（befold-d1-readonly）または環境変数として登録されている
- [x] #2 scripts/analytics-query.sh 経由の SELECT が本番 D1 に対して成功することを実測で確認している
- [x] #3 そのトークンでは書き込みが Cloudflare 側で拒否されることを、staging に対する書き込みの試行で実測している（本番では試さない）
- [x] #4 D1 Read で /query が通らなかった場合の代替案の判断が Implementation Notes に記録されている
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
実測（2026-08-10、Keychain の befold-d1-readonly に登録された Account / D1 / Read のみのトークンで実施）:

読み取り（本番）:
- scripts/analytics-query.sh "SELECT COUNT(*) AS n FROM events" → success、n=319、rows_written=0。D1 Read だけで POST /query の SELECT が通ることが確定した（TASK-395 で未確認としていた前提はこれで解消）。

書き込み（staging に対して実施。本番では試していない）:
- UPDATE events SET kind = kind WHERE 1 → code 7500 'You do not have permission to perform this operation.'
- DELETE FROM events WHERE 1 → 同上
- CREATE TABLE IF NOT EXISTS _readonly_probe (x INTEGER) → 同上

判明した挙動（重要）:
D1 の権限判定は「文の種類」ではなく「実際に変更が発生したか」で行われる。1 行も変更しない書き込み文は成功する:
- DELETE FROM events WHERE 0 → success:true, changed_db:false
- DROP TABLE IF EXISTS _readonly_probe（存在しないテーブル）→ success:true
つまりトークン権限だけでは『書き込み文を実行させない』ことは担保できず、実際の変更が起きる瞬間に止まる形。analytics-query.sh の文面検査は冗長ではなく、書き込み文をそもそも投げない段として必要。この点を site/README.md にも明記した。

代替案（Worker 側の読み取り専用エンドポイント）は不要になったため採らない。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
Account / D1 / Read だけの API トークンを Keychain（befold-d1-readonly）に登録し、TASK-395 で未導入だった「認証」の段を有効化した。コード変更は不要で、scripts/analytics-query.sh がそのまま新トークンを使う。

実測: 本番への SELECT は成功（events 319 行、rows_written=0）。staging への UPDATE / DELETE / CREATE TABLE は D1 側が code 7500 'You do not have permission to perform this operation.' で拒否。

副産物として、D1 の権限判定が『文の種類』ではなく『実際に変更が発生したか』で行われることが分かった（DELETE ... WHERE 0 や存在しないテーブルへの DROP IF EXISTS は成功する）。権限だけでは書き込み文の実行自体は止められないため、analytics-query.sh の文面検査は必要な段として残す。この挙動は site/README.md に記載した。代替案（Worker 側の読み取り専用 API）は不要になったため採らない。
<!-- SECTION:FINAL_SUMMARY:END -->
