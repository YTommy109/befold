/**
 * 記事 1 本を描く枠と、本文の対応表。
 *
 * **本文（コンポーネント）を `lib/articles.ts` に持たせない。** あちらは
 * `lib/pages.ts` が読む（`SITE_PAGES` を導出するため）ので、本文を置くと
 * pages → articles → views/shell → pages の循環になる。メタデータは lib、
 * 描画は views、という分け方は `SITE_PAGES` と `PAGE_VIEWS` の関係と同じ。
 */

import type { FC } from 'hono/jsx'

import type { Article, ArticleLang } from '../lib/articles'
import { pathFor, type SitePage } from '../lib/pages'
import { MedicalExpensesBody } from './article-medical-expenses'
import { T, t } from './i18n'
import { PageShell } from './shell'

/** 記事本文。`Page` ごとに 1 つ。記事を足したらここにも足す（テストが漏れを落とす）。 */
const ARTICLE_BODIES: Partial<Record<Article['page'], FC<{ lang: ArticleLang }>>> = {
  '/usecases/medical-expenses': MedicalExpensesBody,
}

/** その記事の本文。未登録なら null（`articles.test.ts` が全記事について落とす）。 */
export function articleBody(article: Article): FC<{ lang: ArticleLang }> | null {
  return ARTICLE_BODIES[article.page] ?? null
}

/**
 * 記事ページ。公開・ドラフトのどちらも同じ枠で描く。
 *
 * 違うのは URL と、ドラフトに出す但し書きだけ。枠を分けると「ドラフトのときだけ
 * 表示が崩れている」に気づけない。
 */
export const ArticlePage: FC<{
  origin: string
  entry: SitePage
  article: Article
  body: FC<{ lang: ArticleLang }>
}> = ({ origin, entry, article, body: Body }) => {
  const lang = entry.lang
  const isDraft = article.draft === true

  return (
    <PageShell
      origin={origin}
      entry={entry}
      title={`${t(lang, article.title)} — befold`}
      description={t(lang, article.summary)}
      ogType="article"
      // ドラフトは検索結果に出さない。SITE_PAGES に載せていないので sitemap には
      // 出ないが、URL を渡した相手のブラウザ経由で拾われる余地は残るため。
      noindex={isDraft}
      jsonLd={JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'Article',
        headline: t(lang, article.title),
        description: t(lang, article.summary),
        datePublished: article.publishedAt,
        url: `${origin}${entry.path}`,
      })}
    >
      <main>
        <nav class="breadcrumb">
          <a href={pathFor('/usecases', lang)}>
            <T lang={lang} ja="← 記事一覧へ戻る" en="← Back to the article list" />
          </a>
        </nav>

        {isDraft ? <DraftNotice lang={lang} /> : null}

        <article class="article-body">
          <h2>{t(lang, article.title)}</h2>
          <p class="article-date">
            <time datetime={article.publishedAt}>{article.publishedAt}</time>
          </p>
          <Body lang={lang} />
        </article>
      </main>
    </PageShell>
  )
}

/** ドラフトを開いた人に、これが未完成であることを伝える。 */
const DraftNotice: FC<{ lang: ArticleLang }> = ({ lang }) => (
  <p class="draft-notice">
    <T
      lang={lang}
      ja="これは書きかけの下書きです。内容は変わりますし、公開時には URL も変わります。"
      en="This is a work-in-progress draft. The content will change, and the URL will change when it is published."
    />
  </p>
)
