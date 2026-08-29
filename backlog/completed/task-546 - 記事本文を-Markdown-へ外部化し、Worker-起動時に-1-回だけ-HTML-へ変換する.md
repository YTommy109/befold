---
id: TASK-546
title: 記事本文を Markdown へ外部化し、Worker 起動時に 1 回だけ HTML へ変換する
status: Done
assignee: []
created_date: '2026-08-23 08:32'
updated_date: '2026-08-23 08:53'
labels: []
milestone: m-10
dependencies: []
type: enhancement
ordinal: 795000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
## 動機

記事本文が TSX に埋め込まれており、文章として読み返せない。`<T lang={lang} ja="…" en="…" />` が 1 段落ごとに入れ子で並ぶため、校正するにはブラウザで開くしかない。実測: `site/src/views/article-medical-expenses.tsx` は本文 1 本で 300 行超、うち大半が JSX の入れ子。

## 決定済みの方針（B: 起動時に 1 回変換）

本文を `.md` として外に出し、**Worker のモジュール読み込み時に 1 回だけ** HTML へ変換する。リクエストごとの変換は行わない。

TASK-538.1 の設計レビュー項目 6「記事本文を Markdown からパースして描く形にしない。リクエストごとにパースが走る」は**この形なら満たされる**（パースはコールドスタート時の 1 回で、リクエスト経路に乗らない）。当時の決定を覆すものではない。

ビルド時変換（生成物を `.ts` として吐く案）は採らない。生成物とビルド手順が増え、走らせ忘れると古い記事が黙って配信されるため。代償として Markdown パーサが Worker のバンドルに乗ることを受け入れる。

**「原稿置き場を作って、レビュー後に TSX へ取り込む」形は採らない。** 取り込みが手作業のコピーになり、同じ文章が .md と .tsx の 2 箇所に残る。`.md` が唯一の正で、TSX 側に本文を持たない形にする。

## 決めること

- **本文ファイルの置き場と命名**（`site/content/<slug>.<lang>.md` を想定）。`lib/articles.ts` の `slug` と対応させる
- **`.md` の読み込み方**。wrangler / esbuild の text モジュール（`wrangler.toml` の `rules`）で import するか、他の手段か
- **パーサの選定**。befold 本体は markdown-it を同梱している（`BefoldApp/BefoldKit/Resources/`）。同じものを使えば「befold で読んだ原稿と、サイトで公開される記事が同じ見た目になる」性質が付く。バンドルサイズと合わせて判断する
- **素の Markdown で書けない部品の扱い**。現在の記事は次を使っている。生の HTML を書くか、短い記法を用意するかを決める
  - 言語ごとに別画像（`usecase-medical-scan-{ja,en}.png`）
  - `figure class="article-shots"` / `.portrait`
  - ダウンロードボタン（`DOWNLOAD_PATH` と `REQUIRED_OS` を参照する。URL をベタ書きさせない方法が要る）
  - `p class="listing-note"` の注記
- **生の HTML を通すかどうか**。本文は自分たちが書くもので外部入力ではないため通してよいが、その前提を doc コメントに明記する
- **ja / en が揃っていることの担保**。現在は `<T ja= en=>` が構造的に両方を強制しているが、ファイルを分けると片方だけ更新できてしまう。テストで落とす（最低でも「公開記事は両言語のファイルが存在する」）

## 残す部分

記事の枠（見出し・日付・パンくず・ドラフトの断り）と `ARTICLES` のメタデータは TSX のまま。外部化するのは本文だけ。

## 移行対象

既存の 2 記事（`article-ai-code-review.tsx` / `article-medical-expenses.tsx`）を同じタスクで移行し、`ARTICLE_BODIES` の対応表が要らなくなるならそれも畳む。片方だけ移行して 2 つの方式が並ぶ状態を残さない。

## 着手前

**`/review-design` を 1 回通してから実装に入る**（本文の持ち方を変え、記事追加の経路を変える変更のため。CLAUDE.md「実装着手前の設計レビュー」に該当）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 記事本文が .md ファイルにあり、TSX 側に本文の文章が残っていない
- [x] #2 Markdown から HTML への変換がリクエストごとに走らない（モジュールスコープで 1 回だけ実行されることをテストまたはコードで示す）
- [x] #3 既存 2 記事が両方とも新しい方式へ移行され、TSX 直書きの記事が残っていない
- [x] #4 言語ごとに別の画像・ダウンロードボタン・注記が、移行前と同じ HTML で出る（ja / en とも）
- [x] #5 公開記事が両言語の本文ファイルを持つことをテストが担保する
- [x] #6 記事を 1 本足す手順が README なり doc コメントなりに書かれている
- [x] #7 site のテスト・lint・整形チェックが通り、記事ページのレスポンスが移行前と同じ内容を返す
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 実測で確かめた前提（/review-design 実施済み）

- `.md` の text モジュール import: wrangler の `[[rules]] type = "Text"` で通る。vitest-pool-workers も同じ設定を読む（実測）
- markdown-it は workerd で動く（実測）。バンドル増は 110 KB / gzip 47 KB（現行 gzip 93 KB → 約 140 KB、上限 3 MB）
- 起動時 eager 変換のコスト: 11 KB の記事を workerd 上で 4 回 render = 5.0 ms、40 回 = 12.0 ms。startup CPU 上限 400 ms に対し十分小さいので、決定どおり eager を採る
- 本文の消費経路は `src/routes/public.tsx:79` の 1 箇所だけ（grep 実測）
- CSS（`public/style.css:548-607`）は子孫セレクタのみで、本文の親要素構造に依存しない

## 設計

1. **置き場**: `site/content/<slug>.<lang>.md`。`Article.slug` と対応させる
2. **読み込み**: `wrangler.toml` に `[[rules]] type = "Text", globs = ["content/**/*.md"]`。型宣言は `src/content.d.ts`
3. **パーサ**: markdown-it（`html: true`）。befold 本体と同じものなので、befold で読んだ原稿と公開記事の見た目が揃う
4. **変換のタイミング**: `src/views/article-bodies.ts` のモジュールトップレベルで 1 回だけ render し、`Partial<Record<Page, Record<ArticleLang, string>>>` を作る
5. **生 HTML**: 通す。本文は自分たちが書くもので外部入力ではないことを doc コメントに明記する
6. **素の Markdown で書けない部品**
   - 言語ごとの別画像: `.md` が言語ごとに分かれるので素の `![](...)` で済む（言語分岐が消える）
   - `figure class="article-shots"` / `.portrait` / `p class="listing-note"`: 生 HTML を書く
   - ダウンロードボタン + OS 注記: 置換トークン `{{cta}}` を 1 つだけ用意し、`DOWNLOAD_PATH` / `REQUIRED_OS` を参照して展開する。**render 前に生の Markdown ソースへ置換する**（後だと `<p>{{cta}}</p>` に包まれる）

## 設計レビューで決めたこと（実装で必ず入れる）

- **置換トークンの残りを起動時に落とす**（項目 1）。置換後に `{{` が残っていたら throw。綴り違いが本文にそのまま出る経路を塞ぐ
- **公開言語の本文欠落を起動時に throw**（項目 2・9）。`<T ja= en=>` が型で強制していた両言語の担保が失われるため。en を書き忘れると英語ページだけ 404 になり、`SITE_PAGES` には載るので sitemap に 404 URL が出る。検査対象は `articleLangs(article)` が返す言語のみ（`hasEnglish: false` のドラフトを壊さない）
- **対応表の型を `FC` から `string` へ変える**（項目 9）。「TSX 側に本文を持たない」を doc コメントではなく型で守らせる
- **空文字列を「未登録」と扱わない**（項目 1）。`?? null` を使い `|| null` にしない

## AC #2 の担保

「モジュールスコープで 1 回だけ」はテストで直接示せない（参照同一性テストは lazy + memo でも通る）。render 回数のカウンタを本番コードへ入れるのは避け、**参照同一性テスト + コードの形（モジュールトップレベルの const）**で示す。AC #2 は「テストまたはコードで示す」なのでこれで満たす。

## 手順

1. `wrangler.toml` の rules と `src/content.d.ts` を足す
2. `site/content/*.md` 4 本を、既存 TSX から HTML 一致を保って書き起こす
3. `src/views/article-bodies.ts` を作る（import 列挙・置換・render・整合検査）
4. `src/views/article.tsx` を `raw(html)` を描く形へ、`src/views/article-*.tsx` 2 本を削除
5. `test/articles.test.ts` に両言語の本文存在テストと参照同一性テストを足す
6. 移行前後のレスポンス HTML が一致することを確認する（AC #4・#7）
7. 記事を 1 本足す手順を doc コメントに書く（AC #6）
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## 実装した形

- 本文は `site/content/<slug>.<lang>.md` の 4 本（`medical-expenses` / `ai-code-review` × ja/en）
- 読み込みは `wrangler.toml` の `[[rules]] type = "Text", globs = ["**/content/*.md"]`。型宣言は `src/content.d.ts`
- 変換は `src/views/article-bodies.ts` のモジュールトップレベルの `const HTML = renderAll()` で 1 回だけ。markdown-it（`html: true`）
- `src/views/article-medical-expenses.tsx`（352 行）と `src/views/article-ai-code-review.tsx`（163 行）を削除。`ArticlePage` は `bodyHtml: string` を受け取り `raw()` で描く

## glob の指定でつまずいた点（次に触る人向け）

`globs = ["content/**/*.md"]` は**マッチしない**。wrangler の module rule の glob は
エントリ（`src/index.ts`）のディレクトリからの相対パスに当たるため、
`src/views/` からの `../../content/x.md` は `../content/x.md` として評価される。
`**/content/*.md` にして通した（`No loader is configured for ".md" files` で落ちる）。

## /review-design で決めた 4 点、すべて実装に入れた

1. 未知トークン・未展開の `{{` はモジュール読み込み時に throw
2. `articleLangs()` が返す言語の本文欠落もモジュール読み込み時に throw（`hasEnglish: false` のドラフトは対象外）
3. 本文の型を `FC` から `string` へ。本文コンポーネントを置き直すと型エラーになる
4. `?? null` を使い、空の `.md`（書きかけ）を未登録に畳まない

**ガードが空振りしていないことを実測で確認した**（3 つとも壊して落ちるのを見た）。

- en 本文を落とす → `記事 /usecases/medical-expenses の en 本文が無い（content/ に .md を置く）`
- `{{cta}}` を `{{ ctaa }}` → `展開されなかった {{ が残っている`
- `{{ctaa}}` → `未知のトークン {{ctaa}}`

## 移行前後の HTML 比較（AC #4 / #7）

移行前の 4 ページのレスポンスを `wrangler dev` で採取し、`<article class="article-body">` の
中身をタグ間空白を正規化して比較した。**差分は次の 2 種類だけで、どちらも見た目は変わらない。**

- `agent&#39;s` → `agent's`。hono/jsx はアポストロフィをエンティティ化し、markdown-it はしない。テキストとしては同一
- `<blockquote>本文</blockquote>` → `<blockquote><p>本文</p></blockquote>`。markdown 本来の出力で、befold で読んだときと同じ形。`public/style.css:27` の `* { margin: 0 }` があるため `<p>` が入っても余白は増えない

`/usecases/ai-code-review`（ja）は正規化後に完全一致した。

## 実測値

- markdown-it のバンドル増: Worker 全体が 422 KiB / gzip 93 KiB → 620 KiB / gzip 156 KiB（上限 3 MB）
- 起動時 eager 変換: workerd 上で 11 KB の記事を 4 回 render = 5.0 ms、40 回 = 12.0 ms（起動 CPU 上限 400 ms）

## markdownlint

`site/**/*.md` が対象なので、生 HTML で MD033 が 40 件出た。ルートの設定を緩めず
`site/content/.markdownlint-cli2.jsonc` を置き、MD033 を `allowed_elements`
（figure / img / p / ul / li / a）で絞った。無効化ではなく列挙にしてあるので、
新しい要素を使いたくなったら「素の Markdown で書けないか」を先に考える形になる。

## 検証

- `npm test`: 13 ファイル / 393 件すべて成功（記事関連は `articles.test.ts` の 24 件）
- `npm run typecheck`: エラーなし
- `npm run lint`（oxlint --type-aware）: 0 件
- `npm run format:check`: All matched files use the correct format
- `markdownlint-cli2`: 78 ファイル 0 issues
- `wrangler deploy --dry-run`: 成功
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
記事本文を site/content/<slug>.<lang>.md へ外部化し、markdown-it による HTML 変換を views/article-bodies.ts のモジュールトップレベルで 1 回だけ走らせる形にした。既存 2 記事を両方移行して article-medical-expenses.tsx / article-ai-code-review.tsx（計 515 行）を削除し、ArticlePage は bodyHtml: string を受け取る（本文コンポーネントを置き直すと型エラーになる）。着手前に /review-design を 1 回通し、そこで決めた 4 点——未展開トークンと公開言語の本文欠落をモジュール読み込み時に throw、本文の型を FC から string へ、空文字列を未登録に畳まない——をすべて実装に入れ、throw する 3 経路は実際に壊して落ちることを確認した。検証: 移行前の 4 ページのレスポンスを wrangler dev で採取して比較し、差分は &#39; → ' と markdown 本来の <blockquote><p> 包みの 2 種類のみ（* { margin: 0 } があるため見た目は不変）。npm test 393 件・typecheck・oxlint --type-aware・format:check・markdownlint-cli2 78 ファイルすべて通過。バンドルは gzip 93 KiB → 156 KiB（上限 3 MB）、起動時変換は workerd 実測で 4 回 5.0 ms。
<!-- SECTION:FINAL_SUMMARY:END -->
