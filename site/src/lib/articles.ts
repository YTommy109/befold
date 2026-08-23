/**
 * 記事（ユースケース紹介・開発の記録）の定義。**記事の列挙はここだけに置く。**
 *
 * 公開記事の配信パスは `SITE_PAGES`（`lib/pages.ts`）がこの表から導出する。
 * 手で両方に書くと、公開へ切り替えるときに片方だけ直った状態——ドラフトの URL
 * のまま一覧に出る、公開 URL なのに一覧に出ない——を作れてしまう。
 *
 * **記事かどうか・ドラフトかどうかをパスの形で判定しない。** `/usecases/` や
 * `/drafts/` で始まるか、という判定はパスを変えた瞬間に壊れる。どちらもこの表の
 * 内容（載っているか、`draft` が付いているか）だけで決まる。
 *
 * このモジュールは `lib/pages.ts` を import しない（あちらがこちらを読むため）。
 * パスの組み立ては下の純粋関数が持つ。
 */

import type { Page } from '../schema'
import type { Localized } from '../views/i18n'

/** 記事の表示言語。`PageLang` と同じ値だが、循環 import を避けて独立に定義する。 */
export type ArticleLang = 'ja' | 'en'

export type Article = {
  /**
   * 公開後の論理ページ。**ドラフトのうちから確定させておく。**
   *
   * `Page` は `pageSchema`（`src/schema.ts`）の閉じた列挙なので、ここに書くには
   * 先に pageSchema へ値を足す必要がある。これにより「公開時に pageSchema へ
   * 足し忘れて計測が落ちる」経路が型で塞がる。
   */
  page: Page
  /** URL の末尾。`/usecases/<slug>` と `/drafts/<slug>` の両方でこれを使う。 */
  slug: string
  /** 一覧に出す見出し。 */
  title: Localized
  /** 一覧に出す 1〜2 文の要約。 */
  summary: Localized
  /** 公開日（JST の暦日、`YYYY-MM-DD`）。一覧はこの降順で並べる。 */
  publishedAt: string
  /**
   * 書きかけであることの唯一の印。**これを消すことが「公開する」**。
   *
   * ドラフトは `SITE_PAGES` に載らないため、sitemap・旧ホストの 301・hreflang・
   * 言語切替 nav の 4 経路から構造的に外れる。除外条件を経路ごとに書き写さない。
   */
  draft?: true
  /**
   * 英語版を持つか。既定は持つ（公開記事は日英 2 バリアントが不変条件）。
   *
   * ドラフトのうちは日本語だけ先に置けるようにするための逃げ道で、`false` の
   * ままでは公開できない（`articles.test.ts` が公開記事について落とす）。
   */
  hasEnglish?: false
}

/**
 * 記事の全件（ドラフトを含む）。**この配列の順序に意味を持たせない**
 * （並べ替えは `articlesNewestFirst()` が行う）。
 */
export const ARTICLES: readonly Article[] = [
  {
    page: '/usecases/medical-expenses',
    slug: 'medical-expenses',
    title: {
      ja: 'AI 活用で、医療費控除を簡単に!',
      en: 'Medical expense deductions, made easy with AI',
    },
    summary: {
      ja: '領収書をスマートフォンでスキャンしてフォルダーに入れるだけ。あとは Claude が整理して、一覧表まで作ってくれます。',
      en: 'Scan the receipt with your phone and drop it in a folder. Claude files it and builds the ledger for you.',
    },
    publishedAt: '2026-08-23',
  },
  {
    page: '/usecases/ai-code-review',
    slug: 'ai-code-review',
    title: {
      ja: 'AI が書いた変更を読む',
      en: 'Reading what the agent wrote',
    },
    summary: {
      ja: '型検査も lint もテストも通る変更に、人が読んで初めて出る指摘がある。差分表示と「変更のあるファイルのみ」でその往復を回す手順。',
      en: 'Type checks pass and the tests are green, and a human still finds things to fix. How to run that loop with a diff view and a changed-files filter.',
    },
    publishedAt: '2026-08-23',
    // 誤って公開した状態が続いていたため、ドラフトへ戻した（2026-08-23）。
    // 公開時に `/usecases/ai-code-review` が本番で配信されていたので、
    // 再公開するならこのフラグを消すだけでよい（URL は当時と同じに戻る）。
    draft: true,
  },
]

/** 公開済みの記事だけ。一覧と `SITE_PAGES` の導出はこれを使う。 */
export function publishedArticles(): readonly Article[] {
  return ARTICLES.filter((article) => article.draft !== true)
}

/** 書きかけの記事だけ。ドラフト用ルートの登録に使う。 */
export function draftArticles(): readonly Article[] {
  return ARTICLES.filter((article) => article.draft === true)
}

/** 公開日の新しい順。一覧の表示順はここだけが決める。 */
export function articlesNewestFirst(): readonly Article[] {
  return publishedArticles().toSorted((a, b) => b.publishedAt.localeCompare(a.publishedAt))
}

/** その記事が持つ言語。英語版を持たないドラフトは日本語だけ。 */
export function articleLangs(article: Article): readonly ArticleLang[] {
  return article.hasEnglish === false ? ['ja'] : ['ja', 'en']
}

/**
 * 公開記事のパス。`/usecases/<slug>`（英語は `/en` 配下）。
 *
 * 言語ごとの URL の付け方は `SITE_PAGES` の既存ページと同じ規則に揃えてある
 * （日本語を素の URL に置き、英語を `/en` 配下に置く）。
 */
export function articlePath(article: Article, lang: ArticleLang): string {
  return lang === 'ja' ? `/usecases/${article.slug}` : `/en/usecases/${article.slug}`
}

/**
 * ドラフトのパス。**公開記事とは別の URL に置く。**
 *
 * 分けている理由は計測。アクセスは `events.page` に記録され、ダッシュボードの
 * ページ別内訳は生の page 値を畳んで作る（`src/analytics.ts`）。同じ page 値だと
 * 執筆中に自分で開いた回数が公開後の数字に混ざる。
 */
export function draftPath(article: Article, lang: ArticleLang): string {
  return lang === 'ja' ? `/drafts/${article.slug}` : `/en/drafts/${article.slug}`
}

/**
 * ドラフトのアクセスを記録する page 値。**記事ごとに分けない。**
 *
 * `src/events.ts` の doc が書いているとおり、page はページ内訳のカーディナリティを
 * 決める。ドラフトに来るのは公開前の自分（とレビュー相手）のアクセスだけで、
 * 記事ごとの粒度に価値がない。1 つの値に畳んでおけば pageSchema に足す値も
 * これ 1 つで済む。
 */
export const DRAFT_PAGE: Page = '/drafts'
