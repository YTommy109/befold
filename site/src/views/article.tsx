/**
 * 記事 1 本を描く枠。
 *
 * **本文をこの枠に持たせない。** 本文の唯一の正は `site/content/*.md` で、
 * HTML への変換は `views/article-bodies.ts` が受け持つ。ここが受け取るのは
 * 変換済みの HTML 文字列だけ——型が `string` なので、本文コンポーネントを
 * 置き直すことは型エラーになる（TASK-546 で決めた「TSX 側に本文を持たない」を
 * doc コメントではなく型で守らせる）。
 *
 * 本文（や本文の対応表）を `lib/articles.ts` に置かないのは従来どおり。あちらは
 * `lib/pages.ts` が読む（`SITE_PAGES` を導出するため）ので、置くと
 * pages → articles → views/shell → pages の循環になる。メタデータは lib、
 * 描画は views、という分け方は `SITE_PAGES` と `PAGE_VIEWS` の関係と同じ。
 */

import { raw } from 'hono/html'
import type { FC } from 'hono/jsx'

import type { Article, ArticleLang } from '../lib/articles'
import { pathFor, type SitePage } from '../lib/pages'
import { T, t } from './i18n'
import { PageShell } from './shell'

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
  /** 変換済みの本文 HTML（`views/article-bodies.ts` の `articleHtml()` が作る）。 */
  bodyHtml: string
}> = ({ origin, entry, article, bodyHtml }) => {
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
            <T lang={lang} ja="← 事例一覧へ戻る" en="← Back to the use case list" />
          </a>
        </nav>

        {isDraft ? <DraftNotice lang={lang} /> : null}

        <article class="article-body">
          <h2>{t(lang, article.title)}</h2>
          <p class="article-date">
            <time datetime={article.publishedAt}>{article.publishedAt}</time>
          </p>
          {raw(bodyHtml)}
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
