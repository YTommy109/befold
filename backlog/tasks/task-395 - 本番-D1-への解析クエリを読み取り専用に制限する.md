---
id: TASK-395
title: 本番 D1 への解析クエリを読み取り専用に制限する
status: To Do
assignee: []
created_date: '2026-08-09 13:33'
labels: []
dependencies: []
priority: medium
type: task
ordinal: 649000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
解析データを実データで確認する経路として wrangler の d1 execute --remote が使える（2026-08-09 に実行して確認済み）。ただし現在の wrangler トークンは d1 (write) 権限を持っており、同じ経路で本番 events テーブルへの UPDATE / DELETE / DROP も通る。読み取りしか行わないのは運用者側の自制であって、仕組みによる担保がない。

エージェント（Claude）に解析データを見せながら戦略を検討する運用を続けるなら、書き込みを構造的に不可能にしておく。破壊操作の可能性を残したまま自動化を増やすと、events は追記のみで復元手段がないため（バックアップ運用は現在なし）、一度の事故で計測データを全損する。

前提と裏付け:
- 実測: npx wrangler whoami の Token Permissions に 'd1 (write)' が含まれる。アカウントは Tokutomi@degino.com's Account（96b3602a71be49f99732550f9f3dedad）1 つ。
- 実測: (cd site && npx wrangler d1 execute befold-analytics --remote --command 'SELECT ...') が本番 D1 に対して成功する。
- コード参照: 対象 DB は site/wrangler.toml の d1_databases（本番 befold-analytics / staging befold-analytics-staging）。
- 未確認: Cloudflare の API トークンで D1 に読み取り専用スコープを付けられるかは実測していない（D1 の権限が Read / Edit の粒度で分かれているかを Cloudflare ダッシュボードの API Tokens 画面で確認する）。分けられない場合は .claude/settings.json の permissions 側で担保する。
- 選択肢: (a) 読み取り専用 API トークンを発行し、解析用途はそれを使う、(b) .claude/settings.json の permissions で wrangler d1 execute を確認付き（または SELECT で始まるコマンドのみ許可）にする、(c) 両方。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 本番 D1 に対する解析用途のクエリ経路が、書き込み（UPDATE / DELETE / DROP / INSERT）を実行できない形になっている
- [ ] #2 その制限が仕組みで担保されている（運用上の約束や文書だけではない）
- [ ] #3 採用した方式と、検討して採らなかった方式の理由が Implementation Notes に記録されている
- [ ] #4 解析クエリを実行する手順（どのトークン・どのコマンドを使うか）が README または docs に記載され、次回のセッションが手順を再発見しなくてよい
<!-- AC:END -->
