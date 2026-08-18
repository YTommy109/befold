---
id: TASK-496
title: 配布サイトの LP を言語ごとの URL に分けて実際の表示言語を測れるようにする
status: Done
assignee:
  - '@claude'
created_date: '2026-08-16 03:48'
updated_date: '2026-08-17 14:52'
labels: []
milestone: m-7
dependencies: []
priority: medium
type: feature
ordinal: 718500
---

## Description

<!-- SECTION:DESCRIPTION:BEGIN -->
TASK-488.1 の設計レビューで切り出した論点。計測の副産物として決めるべきでない、LP 多言語化そのものの設計判断なので独立させる。

現状、LP と /features は日英の本文を同じ HTML に持ち、`[lang]` 属性 + `hidden` の付け外しで出し分けている（`site/src/views/shared.tsx` の `LANG_SCRIPT`）。表示言語は `localStorage` の `befold-lang` だけで決まり、**未設定なら常に日本語**（`saved && saved !== 'ja'` のときだけ切り替える）。

このためサーバ側からは実際の表示言語が観測できない。TASK-488.1 で記録した `events.browser_lang` は Accept-Language 由来の**ブラウザ言語設定**であり、「英語を求めて来た人の数」は測れるが「英語で読んだ人の数」は測れない（初回訪問の en ユーザーは日本語を読んでいる）。

言語ごとに URL を分ける（`/en` など）と表示言語が確実に測れ、SEO 上も正しくなる（現状は同一 URL に 2 言語が同居し、hreflang も出せない）。一方で canonical / og:url / sitemap.xml / robots.txt / JSON-LD / 旧ホストからの 301（ADR 0007）へ全面的に波及し、既存テストの広い範囲（`site/test/public.test.ts`）を書き換えることになる。

着手前に、言語の決め方（Accept-Language による自動リダイレクト有無、localStorage との優先順位、切替 UI の遷移先）を決めること。自動リダイレクトは検索エンジンのクロールを壊しやすいので、採否とその理由を残す。
<!-- SECTION:DESCRIPTION:END -->

## Acceptance Criteria
<!-- AC:BEGIN -->
- [x] #1 LP と /features が言語ごとの URL で配信され、同一 URL に 2 言語が同居しない
- [x] #2 canonical / og:url / hreflang / sitemap.xml / JSON-LD が言語ごとの URL と整合している
- [x] #3 言語切替 UI が対応する言語の URL へ遷移し、localStorage との関係が決まっている
- [x] #4 events から実際の表示言語が読める（page または新しい列で言語ごとの URL が区別できる）
- [x] #5 Accept-Language による自動リダイレクトの採否とその理由が Implementation Notes に記録されている
- [x] #6 site の vitest と typecheck が通る
<!-- AC:END -->

## Implementation Plan

<!-- SECTION:PLAN:BEGIN -->
## 確定させた設計判断

**D1. URL 設計**: 日本語 = `/` `/features`（現状維持）、英語 = `/en` `/en/features`。日本語側の URL を変えないので既存の被リンク・sitemap・旧ホストからの 301 が生きたまま残る。

**D2. 自動リダイレクトは入れない。** Accept-Language で `/` → `/en` へ飛ばさない。クローラは Accept-Language を送らない／送っても代表的でないため、自動リダイレクトは「英語ページがクロールされない」「日本語ページが英語圏で見られない」のどちらかに倒れる。代わりに両ページの header に相手言語への `<a>` リンクを常設し、hreflang で機械には対応関係を伝える。

**D3. 表示言語は page ではなく新しい列 `display_lang` で持つ。** `page` は論理ページ（`/` = LP、`/features` = 詳細）のままにし、`/en` を page の列挙に足さない。理由: page に `/en` を足すと「ページアクセス」指標（`METRIC_FILTERS.visit.page = '/'`）が LP の半分しか数えなくなり、指標側を集合比較へ広げる改修が要る。論理ページと言語は直交する軸なので列を分けるほうが素直で、TASK-488.2 のページ別内訳・言語別内訳もそのまま 2 軸で出せる。`browser_lang`（求めた言語）と `display_lang`（実際に出した言語）の対で「英語を求めて来た人が英語ページへ辿り着けたか」も測れる。

**D4. ページの列挙を 1 箇所へ寄せる。** `site/src/lib/pages.ts` を新設し `{ path, lang, page, alternatePath }` の表を唯一の定義とする。ここから (a) ルート登録、(b) `pageSchema`、(c) `REDIRECTED_PATHS`（ADR 0007 決定 2 の肯定列挙）、(d) sitemap.xml の URL と `xhtml:link`、(e) hreflang / og:locale を導出する。ADR 0007 自身が「列挙は漏れる」と書いており、実際 `/en` の追加で 5 箇所の同期が要る形になっている。表から導出すれば列挙漏れが構造的に起きない。

**D5. localStorage の言語切替は廃止する。** `LANG_SCRIPT`（shared.tsx:30-49）と `.lang-btn` の onclick を削除し、言語切替は `<a href>` + `aria-current` にする。URL が言語の唯一の状態になる。既存ユーザーの `befold-lang` は読まなくなるが、切替は 1 クリックで済むため移行措置は置かない（読まない値を残す形にしない）。

**D6. JSON-LD は言語ごとに中身を切り替える。** `/features` の FAQPage は現在 `item.question.en` / `answer.en` を固定で選んでおり（features.tsx:140-141）、「構造化データの文面がページ上に見えている」制約（同 :74-75 のコメント、public.test.ts:571 が検査）に依存している。日本語ページから英語本文が消えるため、日本語ページは ja、英語ページは en を使う形にする。LP の SoftwareApplication も description / operatingSystem を言語に合わせる。

## 実装手順

1. **`site/src/lib/pages.ts` を新設**（D4）。`SITE_PAGES` 表と、path → 定義、page+lang → path を引くヘルパー。`site/src/lib/hosts.ts` の `REDIRECTED_PATHS` をこの表から導出する形へ差し替える。
2. **`site/src/schema.ts`**: `displayLangSchema`（'ja' | 'en'）を足し `eventSchema.displayLang` を追加。`pageSchema` は `SITE_PAGES` から導出（`'/' | '/features'` のまま）。
3. **スキーマ**: `schema/schema.sql` に `display_lang TEXT` を ADD COLUMN。`migrate:diff` → `lint` → `local`。
4. **`site/src/events.ts`**: `EventAttributes.displayLang` を追加し INSERT へ 1 列足す。
5. **翻訳ヘルパー**: `site/src/views/i18n.tsx` に `<T ja={} en={} lang={} />` コンポーネントと、属性値用の関数 `t(lang, { ja, en })` を置く。features.tsx:145-155 の既存 `Bilingual` はこれに昇格・統合して削除する。
6. **データ型の統一**: `Feature` のタプル `[string, string]` を `{ title: {ja,en}, body: {ja,en} }` へ、`REQUIRED_OS` / `REQUIRED_OS_JA` の 2 定数を `REQUIRED_OS = {ja, en}` へ揃える（参照元は JSON-LD を含め追う）。file-types.ts の note・SHORTCUTS・FAQ・RENDER_MODE_LABEL は既に `{ja,en}` なのでそのまま `<T>` へ渡せる。
7. **ビューの lang パラメータ化**: `Landing` / `Features` / `SiteHeader` / `SiteFooter` が `lang` を受け取る。`<html lang>`・title・meta description・canonical・og:url・og:locale・hreflang・JSON-LD を lang で組む。日英ペア約 40 箇所を `<T>` へ置換。alt / aria-label 12 箇所は `t()` で訳す。
8. **日本語の title / meta description を新規に書く**（現状は `<html lang="ja">` なのに英語のみという不整合がある）。
9. **ルーティング**: `/en` `/en/features` を追加し、4 ルートすべてが `SITE_PAGES` から登録される形にする。`recordEvent` に `page` と `displayLang` を渡す。`/features` 系は `Cache-Control: no-store` を維持。
10. **sitemap.xml**: 4 URL を列挙し、各 URL に `xhtml:link rel="alternate" hreflang` を付ける。robots.txt は変更不要（`Allow: /`）。
11. **carousel.js**: `document.documentElement.lang` を見る実装（:15）はそのまま動く。切替に追従しない既存のずれは URL 分割で消える。
12. **テスト**: public.test.ts の日英同居前提 5 件（:435-443, :445-453, :509-521, :523-529, :558-573）を「`/` は日本語のみ・`/en` は英語のみ、相手言語が本文に出ない」へ反転。hreflang・canonical・og:locale・sitemap の 4 URL・`display_lang` の記録・`REDIRECTED_PATHS` が `SITE_PAGES` と一致することの構造ガードを追加。
13. `npm run test` / `typecheck` / `markdownlint-cli2`、`site/README.md` の更新。

## 未確認・リスク

- `captionEn` は 8 件すべて未設定（landing.tsx:20, 22-49）。値は `Mermaid` / `SVG` など言語中立語が中心なので、英語ページでもそのまま出す（`captionEn` の分岐自体を削除）。翻訳が要るのは `Source Code` 程度。
- `FILE_TYPE_GROUPS[].label` は翻訳を持たない（file-types.ts:14-25）。`Source code` のみ日本語化の余地があるが、今回は据え置き。
- 英語ページの実表示は未確認。実装後にブラウザで両 URL を開いて確かめる。

## 設計レビュー（/review-design）を受けた修正

- **F-1**: `display_lang` は URL 文字列から導出せず、`SITE_PAGES` の該当エントリの `lang`（= どのビューを配信したかという事実）をルートが渡す。`page` の「URL から導出しない」と兄弟判断を揃える。`<html lang>` / hreflang / og:locale / `display_lang` の 4 者が同じ `lang` から出ることを保証する。`schema.sql` の `display_lang` 列に、page 列と同型の NULL 二義性（download / update_check には無い、列導入前の visit）をコメントで残す。
- **F-2**: `REDIRECTED_PATHS` は `SITE_PAGES` からの単純導出とし、`/en` も含める（旧ホストに被リンクは無いが、例外を作ると導出の唯一性が壊れ D4 の目的を自ら破る）。`SITE_PAGES` の doc に「ここは旧ホストからリダイレクトしてよい HTML ページでもある。`/download`・appcast・`/dl/` を載せてはならない（ADR 0007 決定 2）」を書く。ADR 0007 にも導出元を 1 行追記する。
- **F-3**: `pageSchema` は手書きの列挙のまま残す（`SITE_PAGES` から導出すると `z.enum` がリテラルタプルを取れず `Page` 型が `string` へ広がり、`EventAttributes.page` と `METRIC_FILTERS` の型安全が失われる）。代わりに「`SITE_PAGES` の全 `page` が `pageSchema` に含まれる」ことをテストで固定する。
- **F-6**: 存在しない言語パスは **404 のまま**とする。`/en/download` は作らない（`/download` を単一に保つのは `source:'lp'` 計測を割らないため。英語ページのボタンも相対 `/download`）。`/ja` `/ja/features` も 404（`SITE_PAGES` の唯一性を保つ）。LP 意匠の 404 ページは別タスクへ。
- **F-7**: `/` にも `Cache-Control: no-store` を付ける。**4 ルートすべてに付ける**。現状 `/` は Cache-Control も Expires も無く、488.1 で「ヒューリスティックキャッシュに載り得るので計上が環境依存になる」と結論した条件に LP がそのまま当てはまっている。日英比率を測るのが本タスクの目的なので、取りこぼしが環境依存だと結論が歪む。
- **F-8**: テストの反転は `<body>` 以降に限定し、代表的な訳文リテラルの有無で検査する。HTML 全体を見ると head の `<link rel="alternate" hreflang="en">` や `og:locale:alternate` が `lang="en"` 相当の文字列に引っかかる。
- **F-9**: 手順 12 の「`REDIRECTED_PATHS` が `SITE_PAGES` と一致する」ガードは導出実装では定義上常に真で何も検証しないため差し替える。実際に効くのは次の 5 つ: (a) `/download` が `REDIRECTED_PATHS` に含まれない＝旧ホストの `/download` が 301 でないこと（決定 2 の例外を守る唯一の落ちるもの）、(b) `SITE_PAGES` の全 path が 200 を返し `<html lang>` が表の `lang` と一致、(c) 各ページの hreflang 集合が自己参照を含む全バリアントと一致、(d) sitemap の `<loc>` 集合が `SITE_PAGES` 全件と一致、(e) 各ページの canonical が自分自身を指す。
- **F-4**: hreflang は**自己参照を含む全バリアント**を各ページに置く（`/` にも `hreflang="ja" href="/"` と `hreflang="en" href="/en"` の 2 本）。`x-default` は付けない（Accept-Language で振り分ける入口ページが無いため不要）。`og:locale` は `ja_JP` / `en_US`、相手言語は `og:locale:alternate`。
- **F-5**: `og:image:alt`（landing.tsx:92-95）も lang 化の対象に入れる。`og:image` 本体は言語別不要（本文テキストを含まないスクリーンショット由来の画像なので 1 枚で両言語に使える）。
- **F-10**: D5 の「読まない値を残す形にしない」は事実と食い違う（localStorage の値はブラウザに残る）。UserDefaults 廃止規定と同型なので、**LP 初回表示時に `localStorage.removeItem('befold-lang')` を実行して掃除する**（1 行のインラインスクリプトだけ残す）。stale キーは次に同名キーを再利用したとき誤って読まれるため。
- **CSS**: `.lang-btn.active`（style.css:74）を `.lang-btn[aria-current="page"]` へ書き換える。`.lang-switcher` / `.lang-btn` / `:hover:not(.active)` / `:442` のレスポンシブも `<a>` 化に合わせる。手順 13 の対象に追加。

## Notes へ残す判断（レビューで確定）

- `og:image` は言語別に用意しない。
- D2（自動リダイレクトなし）の理由に「Accept-Language 分岐を入れると `Vary: Accept-Language` が要り、中間キャッシュとの相互作用が読めなくなる」を追加する。
- 496 は**記録まで**。`BreakdownColumn`（analytics.ts:273）の union に `browser_lang` すら入っておらず、`display_lang` を足してもダッシュボードには自動では出ない。表示は TASK-488.2。
<!-- SECTION:PLAN:END -->

## Implementation Notes

<!-- SECTION:NOTES:BEGIN -->
TASK-488.2 より先に着手する（ユーザー判断、2026-08-16）。理由: 496 で表示言語が page 側から直接測れるようになるため、488.2 を先に作ると「ブラウザ言語設定の内訳」とその注記を作った直後に意味が変わる。逆順なら 488.2 を最初から実表示言語の内訳として素直に作れる。

なお、今の「1 つの HTML に日英を入れて hidden で出し分ける」構造を決めた ADR / spec は存在しない（docs/adr/ と docs/superpowers/specs/ を grep して該当なし）。記録された設計判断を覆す変更ではない。

## 実装で確定したこと

**D3（表示言語を page ではなく新列で持つ）は実測でも正しかった。** `METRIC_FILTERS`（site/src/analytics.ts）が読むのは kind / source / page の 3 つだけで、`display_lang` を足しても述語式は 1 文字も変わっていない。page 側に `/en` を足す案だと `visit: { page: '/' }` が LP の半分しか数えなくなり、METRIC_EXPR / metricCondition / KIND_COUNT_COLUMNS が共有する述語を集合比較へ広げる改修が要った。

**D4（SITE_PAGES からの導出）の効き方**: `site/src/lib/pages.ts` の 4 行の表から、ルート登録（public.tsx の for ループ）・`REDIRECTED_PATHS`（hosts.ts）・sitemap.xml の `<loc>` と `xhtml:link`・head の hreflang・`og:locale` を導出した。表から 1 行（`/en/features`）を消すと public.test.ts が 8 件落ちることを実測で確認済み。

**pageSchema は手書きのまま残した**（F-3）。`SITE_PAGES` から導出すると `z.enum` がリテラルタプルを取れず `Page` 型が `string` へ広がり、`EventAttributes.page` と `METRIC_FILTERS` の型安全が失われるため。代わりに「`SITE_PAGES` の全 page が pageSchema に含まれる」テストで両者のずれを検知する。

**JSON-LD の言語切替は既存の不整合も直した。** `/features` の FAQPage は英語固定で `question.en` / `answer.en` を選んでおり、「構造化データの文面がページ上に見えている」制約（public.test.ts の検査）に依存していた。日本語ページから英語本文が消えるため言語ごとに切り替えたところ、既存テストは変更なしで通った。LP の `description` も同様に言語へ合わせ、`operatingSystem` だけは技術的な値なので英語表記のまま揃えた。

**Plan から外したこと**: 手順 6 のうち `Feature` 型のタプル `[string, string]` → `{ title, body }` への変換は**実施しなかった**。15 エントリの多行リテラルを機械変換する必要があり、得られるのは `feature.ja[0]` が `feature.title.ja` になる読みやすさだけで、リスクに見合わない。`<T ja={feature.ja[0]} en={feature.en[0]} />` で問題なく書けている。`REQUIRED_OS` / `REQUIRED_OS_JA` の 2 定数 → `REQUIRED_OS: Localized` への統合は実施した（参照 12 箇所、JSON-LD 含む）。

**localStorage の掃除**（F-10）: `LANG_SCRIPT` は廃止し、`CLEANUP_SCRIPT`（`localStorage.removeItem('befold-lang')` の 1 行）だけを残した。読み手を消すだけでは値がブラウザに残り、次に同名キーを使ったとき誤って読まれるため（UserDefaults 廃止規定と同型）。

**副次的に直った既存のずれ**: `public/carousel.js` は `document.documentElement.lang` を初期化時に 1 回読むだけで、旧実装（LANG_SCRIPT が後から lang を書き換える）では言語切替に追従していなかった。URL 分割でサーバ確定になり、このずれが消えた。

**新規に書いた日本語のメタ情報**: LP と詳細ページの `<title>` / `meta description` は `<html lang="ja">` なのに英語のみという既存の不整合があったため、日本語版を新規に書いた。

**og:image は言語別に用意しない。** 本文テキストを含まないスクリーンショット由来の画像なので 1 枚で両言語に使える。

**存在しない言語パスは 404 のまま**（F-6）。`/en/download` は作らない（`/download` を単一に保たないと `source:'lp'` の計測が言語ごとに割れる。英語ページのボタンも相対 `/download`）。`/ja` `/ja/features` も 404 で、`SITE_PAGES` の唯一性を保つ。LP 意匠の 404 ページは TASK-497 へ切り出した。

## 検証

- `npm test` = 11 files / 204 tests 成功
- `npm run typecheck` = エラーなし
- `npm run migrate:lint` = no diagnostics、`scripts/check-destructive-migrations.sh` = 破壊的な文なし（`display_lang` の ADD COLUMN 1 本）、`migrate:local` 適用成功
- `markdownlint-cli2` = 0 issues
- 破れたら落ちることの実測: (a) hreflang の自己参照を落とす → 1 件失敗、(b) `SITE_PAGES` から `/en/features` を消す → 8 件失敗
- 実レンダリング確認: `/` と `/en` の head・header・hero をダンプし、canonical / hreflang（自己参照込み 2 本）/ og:locale の入れ替わり / JSON-LD の言語一致 / `aria-current` の付き先 / 片方の言語だけが本文に出ることを目視で確認
<!-- SECTION:NOTES:END -->

## Final Summary

<!-- SECTION:FINAL_SUMMARY:BEGIN -->
配布サイトの LP と詳細ページを言語ごとの URL に分けた（日本語 = / と /features、英語 = /en と /en/features）。従来は日英の本文を同一 HTML に入れて hidden で切り替えており、hreflang が原理的に出せず、実際に読まれた言語もサーバから観測できなかった。

要となる構造は site/src/lib/pages.ts の SITE_PAGES（4 行の表）。ここからルート登録・旧ホストからの 301（REDIRECTED_PATHS）・sitemap.xml の loc と xhtml:link・head の hreflang・og:locale の 5 つを導出する。ADR 0007 の決定 2 自身が「列挙は漏れる形で壊れる」と書いており、言語ページの追加でその列挙が 5 箇所に増えたため、書き写す形をやめた。表から 1 行消すと 8 件のテストが落ちることを実測で確認した。

表示言語は page の列挙を増やすのではなく新しい display_lang 列で持った。page に /en を足すと「ページアクセス」指標（METRIC_FILTERS.visit.page='/'）が LP の半分しか数えなくなるため。実測でも METRIC_FILTERS が読むのは kind/source/page の 3 つだけで、列を足しても述語式は変わっていない。browser_lang（求めた言語）と対で読むと「英語を求めて来た人が英語ページへ辿り着けたか」が測れる。

Accept-Language による自動リダイレクトは入れていない（クローラを壊しやすく、Vary: Accept-Language が中間キャッシュとの相互作用を読めなくするため）。相手言語への導線はヘッダのリンクで常設し、現在地は aria-current で示す。4 ルートすべてに Cache-Control: no-store を付けた（1 本でもキャッシュに載ると日英比率が歪むため）。

副産物として既存の不整合を 3 つ直した: html lang=ja なのに title/description が英語のみだった点、FAQ の JSON-LD が英語固定で日本語ページと食い違う形になる点、carousel.js が言語切替に追従していなかった点。

検証: npm test 204 件成功 / typecheck エラーなし / migrate:lint no diagnostics + 破壊的変更なし / markdownlint 0 issues。破れたら落ちること（hreflang の自己参照を落とす、SITE_PAGES から 1 行消す）を実測で確認し、/ と /en の実レンダリングもダンプして目視確認した。
<!-- SECTION:FINAL_SUMMARY:END -->
