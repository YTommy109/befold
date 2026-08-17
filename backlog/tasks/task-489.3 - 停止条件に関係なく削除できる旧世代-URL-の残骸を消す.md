---
id: TASK-489.3
title: 停止条件に関係なく削除できる旧世代 URL の残骸を消す
status: To Do
assignee: []
created_date: '2026-08-16 02:01'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-8
dependencies: []
parent_task_id: TASK-489
priority: medium
type: chore
ordinal: 723000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-489 のうち、出荷済みクライアントに影響しないため停止条件を待たずに片付けられるもの。

## GitHub Pages（第 1 世代）

**まだ有効で稼働している。** 2026-08-16 実測で `gh api repos/YTommy109/befold/pages` が `status: built` / `source: { branch: main, path: /docs }` / `html_url: https://ytommy109.github.io/befold/` を返し、同 URL は HTTP 200 を返す。

配信物はリポジトリの `docs/index.html` ひとつで、中身は meta refresh（`:14`）と `location.replace`（`:54`）で `https://befold.degino.com/?ref=gh-pages` へ飛ばすだけの shim。canonical（`:15`）も新ドメインを指す。

Sparkle も配布バイナリもここは経由しないため、**Pages を無効化して `docs/index.html` を削除しても出荷済みアプリには影響しない**。判断が必要なのは「github.io の URL をブックマーク・被リンクとして持っている訪問者を切り捨ててよいか」だけ。切り捨てたくないなら Pages は残す判断もありうるので、どちらを選ぶかをこのタスクで決めて記録する。

なお `?ref=gh-pages` は参照元計測で使われており（`site/test/public.test.ts:610` が旧ホスト 301 でのクエリ保持を検証）、Pages を止めるならこの参照元が今後増えなくなることを意味する。削除前に実際の流入数をダッシュボードで確認すること。

## 表示だけの古い文字列

- `site/tools/ogp-preview.html:131` — OGP プレビューのモックカードに `befold.tommy109.workers.dev` がハードコードされている。実際の OGP は新ドメインを指しており、この 1 行は表示用の古い文字列。
- `site/README.md` / `docs/` 配下の旧 URL 記述のうち、履歴として意味のあるもの（ADR・superpowers の設計スナップショット）は**書き換えない**。現在の手順を説明している箇所だけを見直す。

## 触らないもの

- `site/src/lib/hosts.ts` の `LEGACY_HOST` / `LEGACY_STAGING_HOST` と `site/wrangler.toml` の `workers_dev = true`。これは生きた設定で、停止は TASK-489.4 の担当。
- ソースリポジトリとしての GitHub リンク。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 GitHub Pages を無効化するか残すかが決定され、理由が記録されている
- [ ] #2 無効化を選んだ場合、docs/index.html が削除され Pages 設定も無効になっている
- [ ] #3 site/tools/ogp-preview.html の旧ホスト表示が現行ドメインに更新されている
- [ ] #4 履歴として残す文書（ADR・設計スナップショット）の旧 URL 記述が書き換えられていない
- [ ] #5 生きた設定（hosts.ts の LEGACY_HOST、wrangler.toml の workers_dev）に手を入れていない
- [ ] #6 GitHub Pages 経由の流入数（参照元 gh-pages）を実データで確認したうえで、無効化するかどうかを判断している
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
【GitHub Pages 流入の統計について】?ref=gh-pages は既に参照元として記録されている。docs/index.html は ?ref=gh-pages を付けて遷移し、resolveReferrer（site/src/lib/referrer.ts）が ?ref= を最優先で採用する。その doc コメントに「GitHub Pages は静的ホスティングのためサーバーサイドリダイレクトができず meta refresh / JS になり Referer は取りこぼしが出る。明示パラメータなら影響を受けずに数えられる」とあり、gh-pages の計測がこの仕組みの動機である。参照元別の内訳はダッシュボードに既にある（site/src/analytics.ts:424）。したがって無効化の判断は新しい計測を待たずに、既存の参照元別内訳の数字を見て行える。人間とロボットの分離が必要なら TASK-488.2 の完了を待つ。

なお 2026-08-16 時点でローカルに読み取り専用 D1 トークン（Keychain の befold-d1-readonly）が無く、実データは未確認。scripts/analytics-query.sh 経由で確認する。

【gh-pages 流入の実測（2026-08-16、本番 D1）】scripts/analytics-query.sh で計測。visit イベントの参照元別内訳のうち referrer='gh-pages' は 16 件 / ユニーク 12（期間 2026-07-30〜2026-08-14）。全て human（bot:% 判定に該当せず）。日別は 07-30: 6件, 07-31: 6件, 08-01: 1件, 08-04: 1件, 08-13: 1件, 08-14: 1件。公開直後に集中し、その後は数日に 1 件のペースで**現在も継続している**（最終 2026-08-14 = 実測の 2 日前）。

比較: 同期間の visit 全体は human 354 / bot 14。gh-pages は human visit の約 4.5%。参照元の上位は (direct) 289、https://t.co 17、gh-pages 16、https://facebook.com 7。

判断材料: ゼロではないため「誰も使っていないから消す」とは言えない。一方で流入元は t.co・facebook 等の SNS 経由が主で、gh-pages は初期の告知経由と推測される。無効化するなら「月 1 件程度の流入を切り捨てる」判断になる。継続するなら docs/index.html は現状維持でよい（shim は既に degino を指しており、実害は無い）。

【参考】update_check は human 132 / bot 2、download は human 35 / bot 1。ただし現時点ではリクエスト先ホストの列が無いため、この 132 件のうち旧ホスト（workers.dev）経由が何件かは分離できない（TASK-488.3 の対象）。

【付随して見つかったもの】参照元に http://befold.degino.com:2052 / :2086 / :8080 / :8880 が各 1 件ある（2026-08-15〜16）。これらは Cloudflare の HTTP 代替ポートで、ポートスキャン等の自動アクセスが human 判定で計上されている可能性がある。ボット判定の精度に関わるため、必要なら別途起票する。
<!-- SECTION:NOTES:END -->
