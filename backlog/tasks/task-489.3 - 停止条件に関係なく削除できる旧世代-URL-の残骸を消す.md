---
id: TASK-489.3
title: 停止条件に関係なく削除できる旧世代 URL の残骸を消す
status: To Do
assignee: []
created_date: '2026-08-16 02:01'
updated_date: '2026-08-16 02:08'
labels: []
milestone: m-8
dependencies: []
parent_task_id: TASK-489
priority: medium
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
<!-- SECTION:NOTES:END -->
