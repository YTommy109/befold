---
id: TASK-488
title: アクセス統計でページ別・閲覧言語別の内訳を人間とロボットに分けて見られるようにする
status: To Do
assignee: []
created_date: '2026-08-16 01:43'
updated_date: '2026-08-16 01:50'
labels: []
milestone: m-7
dependencies: []
priority: medium
ordinal: 717000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
ダッシュボードで「日本語で読んでいる人と英語で読んでいる人の別」と「/features の参照数」を、それぞれロボットと人間に分けて把握できるようにする。

## 現状（実測）

**ページの区別が無い。** `events` テーブルにパス／URL の列は存在せず（desired state は `site/schema/schema.sql:5-26`。列は id / timestamp / kind / version / channel / country / os / ua_summary / visitor_token / referrer / as_org / source）、記録は各ルートハンドラが `recordEvent` を明示的に呼ぶ方式（`site/src/events.ts:28`）。`visit` として計上されるのは `/` のみ（`site/src/routes/public.tsx:19`）。

`/features` は**意図的に記録していない**。`site/src/routes/public.tsx:23-34` のコメントに「visit として記録しない。events テーブルはページを区別する列を持たないため、ここを計上すると LP からの新規獲得を測る指標に別ページの訪問が混ざる」とある。つまり単に計上を足すのではなく、既存の LP 指標を汚さない形にする必要がある。

**閲覧言語を記録していない。** サーバ側で `Accept-Language` を読む箇所は無く、`events` に言語列も無い。言語の出し分けは完全にクライアント側で、`site/src/views/shared.tsx:30-49` の `LANG_SCRIPT` が `localStorage` の `befold-lang` を見て `[lang]` 要素の `hidden` を切り替える。SSR は常に `<html lang="ja">` を出し、日英両方のマークアップを含める。**既定は常に日本語**で、英語話者が来ても切り替えなければ日本語のまま。

**ロボット判定は既にある。** UA からボットを判定し、`ua_summary` に `bot:` 接頭辞付きで保存する（`site/src/lib/visitor.ts:104-123`、既知 28 トークン + 一般パターン）。集計側は接頭辞だけで分離し（`site/src/analytics.ts:133` の `BOT_MATCH`）、`HUMAN_ONLY`（`site/src/analytics.ts:146`）が全集計の WHERE に付く。ダッシュボードには既に「人間の訪問とロボットの巡回」セクションがある（`site/src/views/dashboard.tsx:350-369`）。ボット除外条件が 1 箇所に集約されていることは規約テスト `site/test/analytics.test.ts:299` が担保している。**この仕組みは作り直さず、そのまま使う。**

## 決めるべきこと

- **言語をどう判定するか。** (a) `Accept-Language` ヘッダをサーバ側で記録する（JS 不要・ボットにも付くが、ブラウザ設定であって実際に読んだ言語ではない）、(b) `localStorage` の切替結果を記録する（実際に読んだ言語だが JS 必須で、既定 ja の利用者は切り替えないため「日本語を選んだ人」と「切り替えていない人」が区別できない）、(c) 両方を別の列／別イベントとして持つ。この選択は指標の意味そのものを決めるため、実装前に確定させる。
- **ページをどう持つか。** 列を足して既存クエリを `/` 限定にするか、`kind` を分けるか。いずれにせよ既存の LP 指標（累計・当日・日別・時間帯・バージョン別など）の意味を変えないこと。

## 注意

- 既存行はページ・言語が NULL のままになり遡及分類できない。ダッシュボードには既に同種の注記（`site/src/views/dashboard.tsx` の「遡及分類不可」）があるので、同じ形で示す。
- スキーマ変更は Atlas 運用に従う（desired state を `site/schema/schema.sql` で更新 → `npm run migrate:diff` → `migrate:lint` → local → remote。詳細は `site/README.md:59-73`）。列の改名・再構築は `scripts/check-destructive-migrations.sh` に引っかかるため、追加は `ADD COLUMN` で行う。
- `summarize()` の発行クエリ数には上限テストがある（`site/test/query-count.test.ts:35` の `MAX_QUERIES = 13`）。指標を足す際はクエリ数を線形に増やさない。
- 状態と列を新設する変更のため、各サブタスクで実装着手前に `/review-design` を 1 回回す（`.claude/CLAUDE.md`「実装着手前の設計レビュー」）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [ ] #1 /features の参照数が、/ の参照数と区別してダッシュボードで見られる
- [ ] #2 閲覧言語（日本語 / 英語）の別がダッシュボードで見られる
- [ ] #3 ページ別・言語別のどちらの内訳も、人間とロボットを分けて表示される
- [ ] #4 既存の LP 指標（累計・当日・日別・時間帯・バージョン別など）の意味と数値が、/features の計上によって変わらない
- [ ] #5 遡及分類できない既存行の扱いがダッシュボード上で注記されている
- [ ] #6 site の vitest と typecheck が通る
<!-- AC:END -->
