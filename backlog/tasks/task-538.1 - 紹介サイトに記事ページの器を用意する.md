---
id: TASK-538.1
title: 紹介サイトに記事ページの器を用意する
status: Done
assignee: []
created_date: '2026-08-22 13:05'
updated_date: '2026-08-22 14:40'
labels: []
milestone: m-10
dependencies: []
parent_task_id: TASK-538
priority: medium
ordinal: 783000
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
site に記事（ユースケース・開発計画・リリース記事）を載せる置き場が無い。現状の公開ページは landing / features / releases の 3 つだけ（site/src/lib/pages.ts:37 の SITE_PAGES）。

## Zola を導入しない理由（2026-08-22 に検討・却下）

会社サイトは Zola を使っているが、befold のサイトには持ち込まない。

- site/src/routes/public.tsx:45-55 — 公開ページは SITE_PAGES を回して登録され、**全ページで recordEvent({kind:'visit'}) を打ち、Cache-Control: no-store を付けている**。同ファイルのコメントに『キャッシュに載った応答は Worker を通らず計上できない』と明記。Zola の静的出力を配信すると記事だけアクセス計測が落ちる
- SITE_PAGES が単一の情報源で、そこから sitemap.xml の hreflang 相互リンク（public.tsx:225）と旧ホストのリダイレクト対象（site/src/lib/hosts.ts:62）が導出されている。別系統を持つと二重管理になる
- 数件規模なら PAGE_VIEWS の表（public.tsx:65）に足す方が軽い。この表は『ページを足したら型が漏れを指す』形に意図して作られている

## 設計判断が要る点

記事が増えると Page 型の union が膨らむ。『記事を SITE_PAGES に直接並べる』か『記事レジストリを作って sitemap・計測・リダイレクト列挙へ差し込む』かを決める必要がある。多言語（entry.lang / variantsOf）をどう扱うかも同じ判断に含まれる（記事を日英両方作るのか、日本語のみとするのか）。

**実装着手前に /review-design を 1 回回すこと**（CLAUDE.md『実装着手前の設計レビュー』。新しい経路と値の持ち方を足す変更に当たる）。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 記事ページが SITE_PAGES 由来の仕組み（visit 計測・no-store・sitemap の hreflang・旧ホストのリダイレクト列挙）にすべて乗る
- [x] #2 記事を 1 本足す手順が、既存ページと同じ型の漏れ検知（Record<Page, ...> と同等）で守られる
- [x] #3 多言語の扱いを決め、決めた内容が Notes に残る
- [x] #4 着手前に /review-design を回し、結果を Implementation Plan に反映してある
- [x] #5 befold analytics のダッシュボードで、ユースケース記事のアクセス数をページ別に確認できる
<!-- AC:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
## analytics の AC を足した理由（2026-08-22）

記事ページを SITE_PAGES に載せれば visit イベント自体は記録されるが、**ダッシュボードの『ページアクセス』指標には出ない**。

- `site/src/analytics.ts:60` — `visit: { kind: 'visit', source: null, page: '/' }`。既定の visit 指標は LP（`/`）だけを数える。同 :59 のコメントに『意味と過去データの連続性を保つために page で絞る。ページ別の内訳は別系列』とある
- したがって記事のアクセス数は**ページ別の内訳系列**の側で見えるようにする必要がある。器を作る時点でここまで通すこと（記事を公開してから『数が見えない』と気づく形にしない）

この制約は Zola を却下した理由（静的配信だと Worker を通らず計上できない）と対になっている。計測に載せることが器の要件そのもの。

## /review-design の結果（2026-08-22）

チェックリスト 10 項目を実測付きで当てた。**設計を変えるべきもの 2 件**、実装時に守るもの 3 件。

### 該当した: 項目 2・9「既存の不変条件との衝突／決めた粒度を守らせるもの」

`SITE_PAGES` は現在 6 件すべてが ja/en の 2 バリアントを持つ（`site/src/lib/pages.ts:37`）。この「全ページが 2 言語」は**暗黙の不変条件**になっていて、`variantsOf(entry.page)` が 4 箇所を駆動する。

- 言語切替 nav（`site/src/views/shared.tsx:222`）
- hreflang（`site/src/views/shell.tsx:39`）
- og:locale:alternate（`site/src/views/shell.tsx:48`）
- sitemap の xhtml:link（`site/src/routes/public.tsx:228`）

日本語のみの記事を足すと、この不変条件が**例外ではなく静かな縮退**として破れる（言語切替に日本語ボタンだけが出る、og:locale:alternate が消える）。

**守らせるものが無いことも実測した。** `alternateOf`（2 言語前提を関数に閉じ込めた関数。`pages.ts:76`）は**どこからも呼ばれていない**（grep で定義のみ）。テストも `public.test.ts:1040` が期待値を `SITE_PAGES` から導出しているため、1 バリアントのページは自己参照 1 件で**素通りする**。

→ **実装前に決めること**: 記事を日英で作るか、日本語のみとするか。日本語のみなら (a) 言語切替 nav の見え方をどうするか (b) 1 バリアントを許すことをテストで明示的に固定する。

### 該当した: 項目 1「判定の真実の源」

『記事かどうか』を `/usecases/` のようなパス接頭辞で判定すると、チェック項目 1 が警告する構造判定になる。記事用のレイアウトや一覧を作るなら、`SitePage` に種別を持たせ、パス文字列から導出しない。

### 実装時に守るもの

- **項目 3（消費経路の全列挙）**: `SITE_PAGES` の消費側は実測で 6 箇所。ルート登録（`public.tsx:45`）／`PAGE_VIEWS`（`public.tsx:65`）／`REDIRECTED_PATHS`（`hosts.ts:62`）／sitemap（`public.tsx:225`）／hreflang・og:locale（`shell.tsx`）／言語切替 nav（`shared.tsx`）。加えて `pageSchema`（`site/src/schema.ts:50` の zod enum）が `Page` 型の出所。**pageSchema に足す → `Record<Page, ...>` である PAGE_VIEWS が型エラーになる**、という順で漏れが指されるので、この順序で進める
- **項目 6（高頻度経路のコスト）**: 記事本文を Markdown からパースして描く形にしない。リクエストごとにパースが走る。既存ページと同じく JSX 直書きにする
- **項目 4（新しい状態の表示）**: 記事一覧を作るなら『記事 0 件』の表示が要る。1 本しか無いうちは一覧を作らず landing から直接リンクする案でよい

### 該当しなかったもの

- 項目 5（ライフサイクル）… ページ登録は起動時 1 回のループ。順序依存は『リダイレクト middleware より後にルート登録』のみで、`SITE_PAGES` に足す限り自動で守られる（`site/src/index.ts:37` のコメント）
- 項目 7（測るものと守るもの）… 既存テストは `SITE_PAGES` を回す形なので新ページを自動で覆う（`public.test.ts:561/719/1032/1043`）。ただし上記のとおり 1 バリアントは素通りする
- 項目 8（非同期の世代管理）… 記事は静的。`/releases` のような外部取得を持たない
- 項目 10（型グループの行数）… `scripts/check-type-group-size.sh` は Swift 用。site は TS で対象外

### AC #5（analytics）は追加実装がほぼ要らない

`site/src/analytics.ts:792` の `byPage: foldSplits(visitRows, (row) => row.page ?? '/')` は **raw の page 値を畳むだけ**なので、新しいページの値がそのまま内訳に出る。ダッシュボードの表示も `splitRows(summary.visits.byPage, …)`（`views/dashboard.tsx:733`）で、ページ名の対応表を持っていない。既定の visit 指標（LP のみ / `analytics.ts:60`）は意図どおり変えない。

## 実装（2026-08-22）

ユーザーの判断: **記事は日英両方作る / 記事一覧ページを最初から作る**。前者により、設計レビューで最大の論点だった『全ページ 2 言語』の不変条件をそのまま保てるようになった。

### 入れたもの

- `site/src/lib/articles.ts` … 記事レジストリ。`ARTICLES` は現在空（記事本体は TASK-538.4）。**記事かどうかをパス接頭辞で判定しない**（レビュー項目 1）ため、記事であることはこの表への登録で決まる
- `site/src/views/usecases.tsx` … 一覧ページ。並びは `articlesNewestFirst()` だけが決める（配列の記述順に意味を持たせない）
- `site/src/schema.ts` … `pageSchema` に `/usecases` を追加
- `site/src/lib/pages.ts` … `SITE_PAGES` に `/usecases` と `/en/usecases`
- `site/src/routes/public.tsx` … `PAGE_VIEWS` に `/usecases`
- `site/public/style.css` … `.article-list`。表ではなく縦積みにした（要約の長さがまちまちで、表にすると行高が不揃いになる）
- `site/test/articles.test.ts` … 9 件

### レビューの予告どおりだったこと

`pageSchema` に足した直後、`npm run typecheck` が **`Record<Page, ...>` の漏れを 1 件だけ正確に指した**（`public.tsx(65,7): error TS2741: Property '"/usecases"' is missing`）。レビュー項目 3 で想定した順序（pageSchema → PAGE_VIEWS が型エラー）がそのまま働いた。

AC #5 も予告どおり追加実装が要らなかった。`analytics.ts:792` の byPage は raw の page 値を畳むだけなので、`/usecases` の訪問がそのまま内訳に出る。テストで page=`/usecases` と display_lang が記録されることを確認した。

### 不変条件を守らせるもの（レビュー項目 9）

『全ページが ja/en の 2 バリアント』を `articles.test.ts` で固定した。**これが実際に落ちることを確かめてある**——`/en/usecases` の行を一時的に削って実行し、`AssertionError: page /usecases: expected [ 'ja' ] to deeply equal [ 'en', 'ja' ]` で 3 件失敗することを確認してから復元した。既存の hreflang テスト（`public.test.ts:1040`）は期待値を SITE_PAGES から導出するため 1 バリアントを素通りする点を、この新テストが埋めている。

### 検証（実測）

- `npm run typecheck` … エラーなし
- `npm run lint`（oxlint --type-aware）… 指摘なし
- `npm run format:check` … ずれなし
- `npm test` … 13 ファイル / **378 件 passed**（変更前 369 件 + 新規 9 件）。既存テストは SITE_PAGES を回す形なので `/usecases` を自動で覆っている（sitemap の件数・hreflang・旧ホストの 301）

### 残した判断

`/usecases` は現在 0 件の一覧を返す。landing からはまだリンクしていない（記事が入る TASK-538.4 で繋ぐ）。マージすると空の一覧ページが公開される点は認識のうえで、記事が次のタスクであることから許容した。
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
記事の器を作った。ユーザーの判断で記事は日英両方作ることにしたため、既存の『全ページ 2 言語』の不変条件をそのまま保てている。

入れたもの: 記事レジストリ（src/lib/articles.ts）、一覧ページ（src/views/usecases.tsx）、pageSchema と SITE_PAGES と PAGE_VIEWS への /usecases 登録、.article-list の CSS、テスト 9 件。ARTICLES は現在空で、記事本体は TASK-538.4。

設計レビューの予告が 2 つとも当たった。(1) pageSchema に足した直後 typecheck が Record<Page,...> の漏れを 1 件だけ指した（public.tsx の PAGE_VIEWS）。(2) analytics の byPage は raw の page 値を畳むだけなので、ページ別のアクセス数は追加実装なしで出る。

『全ページ ja/en の 2 バリアント』を守らせるテストを新設し、/en/usecases の行を一時的に削って 3 件失敗することを確認してから復元した（既存の hreflang テストは期待値を SITE_PAGES から導出するため 1 バリアントを素通りする）。

検証: typecheck エラーなし、oxlint --type-aware 指摘なし、format:check ずれなし、npm test が 13 ファイル 378 件 passed（変更前 369 + 新規 9）。
<!-- SECTION:FINAL_SUMMARY:END -->
