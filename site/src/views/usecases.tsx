/** 記事の一覧。ユースケース紹介や開発の記録をここから辿る。 */

import type { FC } from 'hono/jsx'

import { articlePath, articlesNewestFirst, type Article } from '../lib/articles'
import { type PageLang, type SitePage } from '../lib/pages'
import { T, t, type Localized } from './i18n'
import { PageShell } from './shell'

const PAGE_TITLE: Localized = {
  ja: '使い方の記事 — befold',
  en: 'Articles — befold',
}

const PAGE_DESCRIPTION: Localized = {
  ja: 'befold を実際の作業にどう組み込んでいるかを書いた記事の一覧です。',
  en: 'Articles about how befold fits into real work.',
}

/**
 * 記事一覧ページ。
 *
 * 並びは `articlesNewestFirst()` だけが決める（`ARTICLES` の記述順に意味を
 * 持たせない）。意匠は過去バージョン一覧（releases）と同じ枠を使う。
 */
export const Usecases: FC<{ origin: string; entry: SitePage }> = ({ origin, entry }) => {
  const lang = entry.lang
  const articles = articlesNewestFirst()

  return (
    <PageShell
      origin={origin}
      entry={entry}
      title={t(lang, PAGE_TITLE)}
      description={t(lang, PAGE_DESCRIPTION)}
      ogType="website"
      jsonLd={JSON.stringify({
        '@context': 'https://schema.org',
        '@type': 'CollectionPage',
        name: t(lang, PAGE_TITLE),
        description: t(lang, PAGE_DESCRIPTION),
        url: `${origin}${entry.path}`,
      })}
    >
      <main>
        <section class="page-intro">
          {lang === 'ja' ? (
            <>
              <h2>使い方の記事</h2>
              <p>
                befold を実際の作業にどう組み込んでいるかを書いた記事です。
                手元で再現できる形にしてあるので、同じ使い方を試せます。
              </p>
            </>
          ) : (
            <>
              <h2>Articles</h2>
              <p>
                How befold fits into real work. Each article is written so you can reproduce the
                same setup yourself.
              </p>
            </>
          )}
        </section>

        <section class="file-types">
          {articles.length === 0 ? (
            <ArticlesEmpty lang={lang} />
          ) : (
            <ul class="article-list">
              {articles.map((article) => (
                <ArticleItem lang={lang} article={article} />
              ))}
            </ul>
          )}
        </section>
      </main>
    </PageShell>
  )
}

/**
 * 記事が 1 本も無いときの文面。
 *
 * `releases` が「取得失敗」と「0 件」を別の文面にしているのと違い、こちらは
 * 0 件しか起こらない——記事はビルド時に決まる定数（`ARTICLES`）で、取得に
 * 失敗しようがないため。
 */
const ArticlesEmpty: FC<{ lang: PageLang }> = ({ lang }) => (
  <p class="listing-note">
    <T
      lang={lang}
      ja="記事はまだありません。準備ができ次第ここに並びます。"
      en="No articles yet. They will appear here once published."
    />
  </p>
)

const ArticleItem: FC<{ lang: PageLang; article: Article }> = ({ lang, article }) => (
  <li>
    <a href={articlePath(article, lang)}>
      <h3>{t(lang, article.title)}</h3>
    </a>
    <p>{t(lang, article.summary)}</p>
    <p class="article-date">
      <time datetime={article.publishedAt}>{article.publishedAt}</time>
    </p>
  </li>
)
