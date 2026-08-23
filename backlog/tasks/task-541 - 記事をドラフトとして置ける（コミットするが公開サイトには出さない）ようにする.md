---
id: TASK-541
title: 記事をドラフトとして置ける（コミットするが公開サイトには出さない）ようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-22 14:51'
updated_date: '2026-08-22 15:10'
labels: []
milestone: m-10
dependencies:
  - TASK-538.1
priority: medium
ordinal: 791000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
記事を書きかけの状態でコミットし、**公開サイトの記事一覧には現れない**状態を作れるようにする。

## 方針（2026-08-22 ユーザー判断）

**ドラフトは公開記事とは別の URL パスに置く。** 認証はかけない（いずれ公開するものなので、そこまでの保護は要らない）。

別パスにする理由は**統計のノイズを避けられる**こと。アクセスは `events.page` に記録され（`site/src/routes/public.tsx:47`）、ダッシュボードのページ別内訳は生の page 値を畳んで作る（`site/src/analytics.ts:792`）。ドラフトが公開記事と同じ page 値を持つと、執筆中に自分で開いた回数が公開後の数字に混ざる。**別パス = 別の page 値**にすれば、内訳の別の行として分離される。

## なぜ要るか

記事は 1 回では書き上がらない。TASK-538 の医療費記事も、テンプレート・実測・スクリーンショットを別タスクで積み上げてから本文に入る。この間、手元に置いたままではレビューを頼めず、セッションをまたいで失われる。かといってそのまま公開すると書きかけが一覧に並ぶ。

## 現状（実測）

TASK-538.1 で入れた `site/src/lib/articles.ts` の `ARTICLES` が記事の唯一の列挙で、一覧（`site/src/views/usecases.tsx`）は `articlesNewestFirst()` だけを見る。配信自体は `SITE_PAGES`（`site/src/lib/pages.ts`）への登録で決まる。**『一覧に出す』と『URL で配信する』が既に別の表**なので、ドラフトを表現する余地はある。

## 決めること

### 1. 公開時に URL が変わることをどう扱うか

ドラフトの URL と公開後の URL が別になるため、公開の瞬間にパスが変わる。外部からリンクされる前なのでリダイレクトは要らないと思われるが、**レビュー相手に渡した URL が公開後に 404 になる**点は決めておく（404 のままでよいか、公開後の記事へ 301 するか）。

### 2. sitemap と旧ホストの 301 から外すか

どちらも `SITE_PAGES` からの導出（sitemap は `public.tsx:225`、`REDIRECTED_PATHS` は `site/src/lib/hosts.ts:62`）。**別パスにしただけでは sitemap に載る**ので、検索エンジンに拾わせたくないなら別途外す判断が要る。統計のノイズとは別の論点なので、ここで一緒に決めておくこと。

### 3. 『全ページが ja/en の 2 バリアント』をドラフトにも課すか

`site/test/articles.test.ts` がこの不変条件を固定している。日本語のドラフトだけ先に置きたい場面はありそうで、その場合は例外の表し方（ドラフトは対象外とするか、ドラフトも 2 言語必須とするか）を決める。

## 注意

**この機能自体が『公開しないつもりのものが公開される』事故を作りうる。** ドラフトかどうかの判定を 1 箇所（`Article` の属性）に置き、一覧・sitemap・301 の 3 経路がそこだけを見る形にする。経路ごとに条件を書き写すと、片方だけ直った状態で公開される。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 ドラフト記事が公開記事とは別の URL パスで配信される
- [x] #2 ドラフト記事が /usecases の一覧に現れない
- [x] #3 ドラフトのアクセスが、公開記事とは別の page 値として記録される
- [x] #4 sitemap と旧ホストの 301 でのドラフトの扱いを決め、理由を Notes に残す
- [x] #5 ドラフトを公開へ切り替える操作が 1 箇所の変更で済む
- [x] #6 ドラフトが誤って一覧・sitemap に出る変更を入れたらテストが落ちる
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
1. ARTICLES を記事の単一の情報源にし、公開記事の SITE_PAGES エントリをそこから導出する（今は手書き）
2. Article に slug と draft を持たせる。page（最終的な論理ページ）はドラフトのうちから確定させておく
3. ドラフトは SITE_PAGES に載せず、専用のループで /drafts/<slug> に登録する
4. ドラフトのアクセスは単一の page 値 '/drafts' で記録する（記事ごとに増やさない）
5. 循環 import を避けるため、パス生成は articles.ts 側の純粋関数にし、articles.ts からは pages.ts を import しない
6. テストで、ドラフトが一覧・sitemap・301 に出ないことと、公開への切替が draft の削除だけで済むことを固定する
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## /review-design の結果（2026-08-23）

### 単純化を先に検討した

最小の案は『ドラフトを ARTICLES に `draft: true` で入れ、一覧から弾くだけ』。だが**公開時に URL が変わる**ため、SITE_PAGES 側のパスも同時に書き換えることになり、`draft` の削除と SITE_PAGES の編集という **2 箇所**の変更になる。片方だけ直した状態＝『ドラフト URL のまま一覧に出る』『公開 URL なのに一覧に出ない』が作れてしまう。

そこで**公開記事の SITE_PAGES エントリを ARTICLES から導出する**形に変える。記事の `page`（論理ページ）はドラフトのうちから確定させておくので、公開は `draft: true` を消すだけになる（AC #5）。`Article.page` の型が `Page` なので、**pageSchema へ値を足さないとエントリ自体が書けない**——公開時に足し忘れる経路が型で塞がる。

### 項目 1（判定の真実の源）

ドラフトかどうかを**パス接頭辞（`/drafts/` で始まるか）で判定しない**。`Article.draft` が唯一の真実で、パスはそこから導出する。TASK-538.1 で `ARTICLES` に書いた『記事かどうかをパスで判定しない』と同じ理由。

### 項目 2・3（不変条件との衝突／消費経路の全列挙）

**ドラフトを SITE_PAGES に載せない**ことで、sitemap（`public.tsx:225`）・旧ホストの 301（`hosts.ts:62`）・hreflang（`shell.tsx:39`）・言語切替 nav（`shared.tsx:222`）の 4 経路から**構造的に外れる**。『sitemap から除外する条件』を書き足す形にすると、経路ごとに条件を書き写すことになり片方だけ直る余地が残る。AC #4 はこの構造で満たす。

副次的に、`articles.test.ts` の『全ページが ja/en の 2 バリアント』も SITE_PAGES ベースなのでドラフトには課されない。**日本語のドラフトだけ先に置ける**（決めること 3 の答え）。

### 項目 4（新しい状態に対応する表示）

ドラフトの一覧は作らない。URL を直接渡す運用なので、`/drafts` の索引ページは置かない（置くと『公開しないつもりのものの一覧』が公開される）。

### 項目 6（高頻度経路のコスト）

SITE_PAGES を導出に変えるが、モジュール初期化時に 1 回評価される定数のままにする。リクエストごとに組み立てない。

### 項目 9（決めた粒度を守らせるもの）

- ドラフトが sitemap・一覧・301 に出たら落ちるテストを置く
- 公開への切替が `draft` の削除だけで済むことを、ドラフトと公開の両方を持つフィクスチャで固定する

### 分析の page 値は記事ごとに増やさない

`site/src/events.ts:26` の doc が『パスから導出するとページ内訳のカーディナリティが発散する』と書いている。ドラフトは公開前の自分のアクセスしかないので、記事ごとの粒度に価値がない。**全ドラフト共通の単一値 `/drafts`** で記録し、pageSchema に足す値も 1 つだけにする。

### 循環 import の回避

`pages.ts` が `articles.ts` を import する向きにするため、`articles.ts` からは `pages.ts` を import しない。パス生成は articles.ts 側の純粋関数（slug と lang から組み立てる）にする。現在 `articlePath` が `pathFor` を呼んでいるので、ここを書き換える。

## 実装（2026-08-23）

### 決めたこと 3 つ（Description の『決めること』への回答）

1. **公開時に URL が変わる件**: ドラフト URL は公開後 404 にする。リダイレクトは張らない。ドラフトの URL は外部からリンクされない前提で渡すものであり、301 を残すと『公開しないつもりだった URL』が恒久的に生き続ける。テストで 404 を固定した
2. **sitemap と旧ホストの 301**: **どちらからも外す。除外条件を書くのではなく、ドラフトを `SITE_PAGES` に載せないことで構造的に外した。** sitemap（`public.tsx`）・301（`hosts.ts`）・hreflang（`shell.tsx`）・言語切替 nav（`shared.tsx`）の 4 経路はすべて `SITE_PAGES` からの導出なので、1 つ載せないだけで 4 つとも外れる。加えて `noindex, nofollow` を meta で出す（URL を渡した相手のブラウザ経由でクロールされる余地は残るため）
3. **日本語だけのドラフト**: 許す。`Article.hasEnglish: false` で表す。ただし**その状態のままでは公開できない**——`articles.test.ts` が『公開記事は英語版を持つ』で落とす

### 構造

- `lib/articles.ts` が記事の唯一の情報源。**公開記事の `SITE_PAGES` エントリはここから導出**（手で二重に書かない）
- `views/article.tsx` が本文の対応表と記事ページの枠。**本文コンポーネントを lib 側に置かない**——`pages.ts` が `articles.ts` を読むため、本文を置くと pages → articles → views/shell → pages の循環になる。メタデータは lib・描画は views という分け方は `SITE_PAGES` と `PAGE_VIEWS` の関係と同じ
- ルート登録を 3 系統に分けた: 固定ページ（`FIXED_PAGES` → `PAGE_VIEWS`）／公開記事／ドラフト。記事を分けたのは**本文が 1 本ずつ違い、1 ページ 1 ビューの対応表に収まらない**ため
- `PAGE_VIEWS` の型を `Record<Page, ...>` から `Record<FixedPage, ...>` へ絞った。そのままだとビューを持たない記事ページや `/drafts` までビューを要求される

### 公開が 1 箇所で済むことの実測

`draft: true` の 1 行を消して実行し、**配信 URL・sitemap・一覧・noindex がすべて公開側へ切り替わる**ことを確認した（`/usecases/medical-expenses` が 200、`/drafts/medical-expenses` が 404、sitemap と一覧に公開 URL が出る、noindex が消える）。確認後に復元してある。

これが成り立つのは、記事の `page` 値をドラフトのうちから確定させ、pageSchema にも先に足してあるため。`Article.page` の型が `Page` なので、**pageSchema へ足す前はエントリ自体が書けない**（公開時の足し忘れが型で塞がる）。

### 漏れの検知の実測

`SITE_PAGES` の導出を `publishedArticles()` から `ARTICLES` に変えて（＝ドラフトを公開経路へ載せて）実行し、2 件が落ちることを確認した——『ドラフトの page が SITE_PAGES に載らない』『ドラフトのパスが sitemap.xml に出ない』。確認後に復元してある。

### スコープについて

ドラフトを配信するには実体が必要なので、医療費記事を `draft: true` で 1 件登録し、**骨子だけの本文**（`views/article-medical-expenses.tsx`）を置いた。見出し構成・スクリーンショット 3 枚・テンプレートへのリンクまでで、本文は TASK-538.4 で書く。仕組みを実際に動かして確かめるための最小の実体であり、記事を書いたわけではない。

### 検証（実測）

- `npm run typecheck` … エラーなし
- `npm run lint`（oxlint --type-aware）… 指摘なし
- `npm run format:check` … ずれなし
- `npm test` … 13 ファイル / **386 件 passed**（変更前 378 件 + 新規 8 件）
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
記事をドラフトとして置ける仕組みを入れた。ドラフトは /drafts/<slug> に置き、公開記事の /usecases/<slug> とは別の URL・別の page 値（/drafts に畳む）で扱う。認証はかけない。

要点は、除外条件を書かずに構造で外したこと。ドラフトを SITE_PAGES に載せないだけで、そこから導出される sitemap・旧ホストの 301・hreflang・言語切替 nav の 4 経路すべてから自動的に外れる。あわせて noindex を出す。

公開は draft: true の 1 行を消すだけで済む。記事の page 値をドラフトのうちから確定させ、Article.page の型を Page にしてあるため、pageSchema への足し忘れも型で塞がる。

検証: draft を消して配信 URL・sitemap・一覧・noindex がすべて公開側へ切り替わることを実測。逆に SITE_PAGES の導出を ARTICLES に変えて（ドラフトを漏らして）2 件のテストが落ちることも実測。どちらも確認後に復元した。typecheck・lint・format:check いずれも指摘なし、npm test が 386 件 passed（変更前 378 + 新規 8）。
<!-- SECTION:FINAL_SUMMARY:END -->
