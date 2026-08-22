/**
 * 記事（ユースケース紹介・開発の記録）の定義。**記事の列挙はここだけに置く。**
 *
 * `SITE_PAGES`（`lib/pages.ts`）が「配信するパス」の唯一の表であるのに対し、
 * こちらは「記事という種類のページ」の唯一の表。両者を分けているのは、
 * 一覧に並べたい・公開日で並べ替えたいといった性質が記事にしか無いため。
 *
 * **記事かどうかをパスの接頭辞（`/usecases/` で始まるか）で判定しない。**
 * 同じ形が将来ふつうのページに現れうるし、パスを変えた瞬間に判定が壊れる。
 * 記事であることはこの表に載っているかどうかで決まる。
 */

import type { Page } from '../schema'
import type { Localized } from '../views/i18n'
import { pathFor, type PageLang } from './pages'

export type Article = {
  /** 記事の論理ページ。`SITE_PAGES` にも同じ値で載せる。 */
  page: Page
  /** 一覧に出す見出し。 */
  title: Localized
  /** 一覧に出す 1〜2 文の要約。 */
  summary: Localized
  /** 公開日（JST の暦日、`YYYY-MM-DD`）。一覧はこの降順で並べる。 */
  publishedAt: string
}

/**
 * 公開している記事。新しいものが先に来るよう `articlesNewestFirst()` で並べ替える
 * （この配列自体の順序に意味を持たせない——並べ替えを忘れた追記で順序が崩れる）。
 */
export const ARTICLES: readonly Article[] = []

/** 公開日の新しい順。一覧の表示順はここだけが決める。 */
export function articlesNewestFirst(): readonly Article[] {
  return ARTICLES.toSorted((a, b) => b.publishedAt.localeCompare(a.publishedAt))
}

/** その記事を指定言語で配信しているパス。宛先を文字列で書かないための入口。 */
export function articlePath(article: Article, lang: PageLang): string {
  return pathFor(article.page, lang)
}
