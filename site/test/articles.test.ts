/**
 * 記事の器（TASK-538.1）が守るべき性質。
 *
 * ここが押さえるのは、記事を 1 本足すときに**黙って落ちる**もの——
 * `SITE_PAGES` への登録漏れ、片方の言語だけの登録、計測に載らないページ。
 * 型で指されるもの（`Record<Page, ...>` の網羅）はテストにしない。
 */

import { createExecutionContext, env, waitOnExecutionContext } from 'cloudflare:test'
import { beforeEach, describe, expect, it } from 'vitest'

import app from '../src/index'
import {
  ARTICLES,
  articlePath,
  articlesNewestFirst,
  draftArticles,
  draftPath,
  publishedArticles,
} from '../src/lib/articles'
import { SITE_PAGES, variantsOf } from '../src/lib/pages'

const UA = 'Mozilla/5.0 (Macintosh; Intel Mac OS X 14_5) AppleWebKit/605.1.15 Safari/605.1.15'
const ORIGIN = 'https://befold.example'

async function call(path: string): Promise<Response> {
  const request = new Request(`${ORIGIN}${path}`, {
    headers: { 'User-Agent': UA, 'CF-Connecting-IP': '203.0.113.5', 'CF-IPCountry': 'JP' },
    redirect: 'manual',
  })
  const ctx = createExecutionContext()
  const response = await app.fetch(request, env, ctx)
  await waitOnExecutionContext(ctx)
  return response
}

describe('配信ページの言語バリアント', () => {
  /**
   * **全ページが日本語版と英語版の両方を持つ。**
   *
   * この不変条件は `variantsOf` を通じて 4 箇所を駆動している——言語切替 nav
   * （views/shared.tsx）・hreflang と og:locale:alternate（views/shell.tsx）・
   * sitemap の xhtml:link（routes/public.tsx）。片方の言語しか無いページを足すと、
   * 例外にはならず「言語切替に 1 つしかボタンが出ない」「og:locale:alternate が
   * 消える」という静かな縮退になる。既存の hreflang テストは期待値を
   * `SITE_PAGES` から導出しているため、1 バリアントのページは素通りする。
   * ここで明示的に落とす。
   */
  it('すべての論理ページが ja と en の 2 バリアントを持つ', () => {
    const pages = [...new Set(SITE_PAGES.map((entry) => entry.page))]
    for (const page of pages) {
      const langs = variantsOf(page)
        .map((variant) => variant.lang)
        .toSorted()
      expect(langs, `page ${page}`).toEqual(['en', 'ja'])
    }
  })

  it('同じパスを 2 つのページに割り当てていない', () => {
    const paths = SITE_PAGES.map((entry) => entry.path)
    expect(new Set(paths).size).toBe(paths.length)
  })
})

describe('記事の登録', () => {
  /**
   * 記事は `ARTICLES` と `SITE_PAGES` の両方に載って初めて配信される。
   * 片方だけだと、一覧にリンクが出るのに 404 になる（あるいはその逆）。
   */
  it('すべての公開記事の page が SITE_PAGES に両言語で載っている', () => {
    for (const article of publishedArticles()) {
      const langs = variantsOf(article.page)
        .map((variant) => variant.lang)
        .toSorted()
      expect(langs, `article ${article.page}`).toEqual(['en', 'ja'])
    }
  })

  /** 日本語だけのドラフトは許すが、その状態のまま公開はできない。 */
  it('公開記事は英語版を持つ', () => {
    for (const article of publishedArticles()) {
      expect(article.hasEnglish, `article ${article.page}`).not.toBe(false)
    }
  })

  it('slug が記事どうしで重複していない', () => {
    const slugs = ARTICLES.map((article) => article.slug)
    expect(new Set(slugs).size).toBe(slugs.length)
  })

  it('公開日は YYYY-MM-DD で、一覧は新しい順に並ぶ', () => {
    for (const article of ARTICLES) {
      expect(article.publishedAt).toMatch(/^\d{4}-\d{2}-\d{2}$/u)
    }
    const dates = articlesNewestFirst().map((article) => article.publishedAt)
    expect(dates).toEqual(dates.toSorted().toReversed())
  })
})

describe('/usecases', () => {
  it('日本語版と英語版がそれぞれの言語で本文を返す', async () => {
    const ja = await (await call('/usecases')).text()
    expect(ja).toContain('使い方の記事')
    expect(ja).toContain('<html lang="ja">')

    const en = await (await call('/en/usecases')).text()
    expect(en).toContain('Articles')
    expect(en).toContain('<html lang="en">')
  })

  /** 記事が 0 件のときに「準備中」と伝える。取得失敗は起こらない（定数のため）。 */
  it('記事が 0 件なら、その旨を出す', async () => {
    const html = await (await call('/usecases')).text()
    // 条件分岐で expect を囲まない。記事が増えても意味が変わらないよう、
    // 「0 件のときだけ出る」という関係そのものを 1 つの式で固定する。
    expect(html.includes('記事はまだありません')).toBe(publishedArticles().length === 0)
  })

  it('計測を Worker で受けられるよう Cache-Control: no-store を付ける', async () => {
    const response = await call('/usecases')
    expect(response.headers.get('Cache-Control')).toBe('no-store')
  })
})

describe('記事ページの計測', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM events').run()
  })

  /**
   * ダッシュボードの「ページ別」内訳は events.page を畳んで作る
   * （src/analytics.ts の byPage）。ページ名の対応表を持たないので、
   * ここに値が入りさえすれば内訳に出る。既定の visit 指標が LP だけを
   * 数えるのは意図した仕様なので、そちらは変えない。
   */
  it('/usecases への訪問が page=/usecases として記録される', async () => {
    await call('/usecases')
    const row = await env.DB.prepare(
      "SELECT page, display_lang FROM events WHERE kind = 'visit' ORDER BY id DESC LIMIT 1",
    ).first<{ page: string | null; display_lang: string | null }>()
    expect(row?.page).toBe('/usecases')
    expect(row?.display_lang).toBe('ja')
  })

  it('英語版は同じ page で display_lang だけが変わる', async () => {
    await call('/en/usecases')
    const row = await env.DB.prepare(
      "SELECT page, display_lang FROM events WHERE kind = 'visit' ORDER BY id DESC LIMIT 1",
    ).first<{ page: string | null; display_lang: string | null }>()
    expect(row?.page).toBe('/usecases')
    expect(row?.display_lang).toBe('en')
  })
})

describe('ドラフト記事', () => {
  beforeEach(async () => {
    await env.DB.prepare('DELETE FROM events').run()
  })

  /**
   * ドラフトが公開経路へ漏れないことは、**除外条件ではなく構造**で担保している
   * ——`SITE_PAGES` に載せないので、そこから導出される sitemap・旧ホストの 301・
   * hreflang・言語切替 nav の 4 経路すべてから自動的に外れる。ここではその
   * 結果を落とす（経路ごとに条件を書き写す形に戻したら、このテストが気づく）。
   */
  it('ドラフトの page が SITE_PAGES に載らない', () => {
    for (const article of draftArticles()) {
      expect(variantsOf(article.page), `draft ${article.page}`).toEqual([])
    }
  })

  it('ドラフトのパスが sitemap.xml に出ない', async () => {
    const body = await (await call('/sitemap.xml')).text()
    for (const article of draftArticles()) {
      expect(body, `draft ${article.slug}`).not.toContain(draftPath(article, 'ja'))
      // 公開後のパスも、まだ公開していないので出てはいけない。
      expect(body, `article ${article.slug}`).not.toContain(articlePath(article, 'ja'))
    }
  })

  it('ドラフトが記事一覧に出ない', async () => {
    const html = await (await call('/usecases')).text()
    for (const article of draftArticles()) {
      expect(html, `draft ${article.slug}`).not.toContain(draftPath(article, 'ja'))
      expect(html, `article ${article.slug}`).not.toContain(articlePath(article, 'ja'))
    }
  })

  it('ドラフトは専用パスで配信され、公開後のパスはまだ 404', async () => {
    for (const article of draftArticles()) {
      const draft = await call(draftPath(article, 'ja'))
      expect(draft.status, `draft ${article.slug}`).toBe(200)

      const published = await call(articlePath(article, 'ja'))
      expect(published.status, `article ${article.slug}`).toBe(404)
    }
  })

  it('ドラフトには noindex と、書きかけである旨の断りが入る', async () => {
    for (const article of draftArticles()) {
      const html = await (await call(draftPath(article, 'ja'))).text()
      expect(html, `draft ${article.slug}`).toContain('name="robots" content="noindex, nofollow"')
      expect(html, `draft ${article.slug}`).toContain('書きかけの下書き')
    }
  })

  /**
   * ドラフトのアクセスは記事ごとに分けず `/drafts` へ畳む。公開後の記事の
   * page 値（`/usecases/...`）に混ざらないことが、統計のノイズを避ける要点。
   */
  it('ドラフトのアクセスが page=/drafts として記録される', async () => {
    const [article] = draftArticles()
    if (article === undefined) return

    await call(draftPath(article, 'ja'))
    const row = await env.DB.prepare(
      "SELECT page FROM events WHERE kind = 'visit' ORDER BY id DESC LIMIT 1",
    ).first<{ page: string | null }>()
    expect(row?.page).toBe('/drafts')
  })
})
