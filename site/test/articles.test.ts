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
  articleLangs,
  articlePath,
  articlesNewestFirst,
  draftArticles,
  draftPath,
  publishedArticles,
} from '../src/lib/articles'
import { SITE_PAGES, variantsOf } from '../src/lib/pages'
import { articleHtml } from '../src/views/article-bodies'
import { downloadHref, REQUIRED_OS } from '../src/views/shared'

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
    expect(ja).toContain('使い方の事例')
    expect(ja).toContain('<html lang="ja">')

    const en = await (await call('/en/usecases')).text()
    expect(en).toContain('Use cases')
    expect(en).toContain('<html lang="en">')
  })

  /** 記事が 0 件のときに「準備中」と伝える。取得失敗は起こらない（定数のため）。 */
  it('記事が 0 件なら、その旨を出す', async () => {
    const html = await (await call('/usecases')).text()
    // 条件分岐で expect を囲まない。記事が増えても意味が変わらないよう、
    // 「0 件のときだけ出る」という関係そのものを 1 つの式で固定する。
    expect(html.includes('事例はまだありません')).toBe(publishedArticles().length === 0)
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

/**
 * 本文を `site/content/*.md` へ外部化した後（TASK-546）に守るべき性質。
 *
 * 移行前は `<T lang={lang} ja="…" en="…" />` が**構造的に**両言語を強制し、
 * 本文の描画はコンポーネントの呼び出しだった。ファイルを分けたことでその 2 つの
 * 担保が失われるので、ここで落とす。
 */
describe('記事本文（Markdown 外部化）', () => {
  /**
   * 公開する言語の本文が揃っていること。
   *
   * `en` を書き忘れると英語ページだけ 404 になり、`SITE_PAGES` には載ったままなので
   * **sitemap に 404 の URL が出る**という静かな壊れ方をする。`article-bodies.ts` は
   * モジュール読み込み時にも同じ検査をして throw するが、そちらは「Worker が
   * 起動しない」形なので、原因が読めるようにここでも落とす。
   */
  it('公開記事は articleLangs が返すすべての言語の本文を持つ', () => {
    for (const article of publishedArticles()) {
      for (const lang of articleLangs(article)) {
        const html = articleHtml(article, lang)
        expect(html, `article ${article.page} (${lang})`).not.toBeNull()
        expect(html?.length, `article ${article.page} (${lang})`).toBeGreaterThan(0)
      }
    }
  })

  /**
   * **Markdown のパースがリクエストごとに走らない**（AC #2）。
   *
   * 「モジュールスコープで 1 回だけ」そのものはテストで直接示せないので、
   * 「呼ぶたびに変換していない」ことを参照の同一性で落とす。毎回 render すれば
   * 内容が同じでも別の文字列インスタンスになるため `toBe` が失敗する。
   * 起動時 eager であることはコードの形（`article-bodies.ts` のトップレベルの
   * `const HTML`）が示す。
   */
  it('本文 HTML は呼ぶたびに作り直されない', () => {
    for (const article of publishedArticles()) {
      for (const lang of articleLangs(article)) {
        expect(articleHtml(article, lang)).toBe(articleHtml(article, lang))
      }
    }
  })

  /**
   * 置換トークンが本文にそのまま出ていないこと。
   *
   * `article-bodies.ts` は未知のトークンと未展開の `{{` を読み込み時に throw
   * するが、それは `.md` 側の書き方の話。ここが見るのは**配信された HTML**に
   * 中括弧の残骸が出ていないという結果のほう。
   */
  /**
   * `.md` には `../public/images/foo.png` のような**実在する相対パス**を書く
   * （befold やエディタで開いたときに画像とリンクが解決できるように）。配信時は
   * `toSitePaths()` が `/images/foo.png` へ畳む。ここが壊れると、記事は 200 を
   * 返したまま画像だけが出ない形になるので、両側から落とす。
   */
  it('画像とサイト内リンクが配信パスへ書き換えられる', () => {
    for (const article of publishedArticles()) {
      for (const lang of articleLangs(article)) {
        const html = articleHtml(article, lang) ?? ''
        expect(html, `article ${article.page} (${lang})`).not.toContain('../')
      }
    }

    const medical = publishedArticles().find((a) => a.slug === 'medical-expenses')
    expect(medical, 'medical-expenses が公開記事に無い').toBeDefined()
    const html = medical === undefined ? '' : (articleHtml(medical, 'ja') ?? '')
    expect(html).toContain('src="/images/usecase-medical-tsv.png"')
    expect(html).toContain('href="/templates/medical-expenses/README.md"')
  })

  it('配信される本文にトークンの残骸が出ない', () => {
    for (const article of publishedArticles()) {
      for (const lang of articleLangs(article)) {
        expect(articleHtml(article, lang), `article ${article.page} (${lang})`).not.toContain('{{')
      }
    }
  })
})

/**
 * 素の Markdown で書けない部品が、移行前と同じ HTML で出ること（AC #4）。
 *
 * 対象は 3 つ——(1) 言語ごとに別のスクリーンショット、(2) `DOWNLOAD_PATH` と
 * `REQUIRED_OS` を参照するダウンロード導線（`{{cta}}`）、(3) `listing-note` の注記。
 * どれも `<T>` や TS の定数参照でしか書けなかったもので、外部化で失われやすい。
 */
describe('医療費控除の記事に残す部品', () => {
  const ARTICLE = '/usecases/medical-expenses'

  it('スクリーンショットが言語ごとに出し分けられる', async () => {
    const ja = await (await call(ARTICLE)).text()
    expect(ja).toContain('/images/usecase-medical-scan-ja.png')
    expect(ja).not.toContain('/images/usecase-medical-scan-en.png')

    const en = await (await call(`/en${ARTICLE}`)).text()
    expect(en).toContain('/images/usecase-medical-scan-en.png')
    expect(en).not.toContain('/images/usecase-medical-scan-ja.png')
  })

  /** 縦長のスクリーンショットは `portrait` で幅を絞る（style.css の該当規則）。 */
  it('縦長のスクリーンショットに portrait が付く', async () => {
    const html = await (await call(ARTICLE)).text()
    expect(html).toContain('<figure class="article-shots portrait">')
  })

  /**
   * ダウンロード導線は `{{cta}}` の展開結果。**URL と対応 OS を本文へベタ書き
   * させない**ためのトークンなので、`downloadHref()` / `REQUIRED_OS` の値が
   * そのまま出ることを見る（本文に固定文字列で書かれていたら、定数を変えた
   * ときにここが落ちる）。
   *
   * href には記事の `?ref=` が載る（TASK-549）。ここが素の `/download` に戻ると
   * 「どの記事から押されたか」が記録に残らないので、完全一致で固定する。
   */
  it('ダウンロードボタンと OS 注記が定数から組み立てられる', async () => {
    const href = downloadHref('/usecases/medical-expenses')
    expect(href).toContain('?ref=usecases-medical-expenses')

    const ja = await (await call(ARTICLE)).text()
    expect(ja).toContain(`<a href="${href}" class="btn-primary">Mac 版をダウンロード</a>`)
    expect(ja).toContain(
      `<p class="listing-note">${REQUIRED_OS.ja}が必要です。無料で使えます。</p>`,
    )

    const en = await (await call(`/en${ARTICLE}`)).text()
    expect(en).toContain(`<a href="${href}" class="btn-primary">Download for Mac</a>`)
    expect(en).toContain(`<p class="listing-note">Requires ${REQUIRED_OS.en}. Free to use.</p>`)
  })

  it('税務の断りが listing-note として出る', async () => {
    const ja = await (await call(ARTICLE)).text()
    expect(ja).toContain('<p class="listing-note">※ この記事は税務のアドバイスではありません。')
    expect(ja).toContain('<ul class="listing-note">')
  })
})
